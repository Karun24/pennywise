import '../../database/default_categories.dart';
import '../../models/category.dart';
import '../../models/transaction_entry.dart';

/// How a category was chosen. Shown to the user so it's clear this is
/// rule-based, on-device logic rather than a cloud AI model.
enum MatchSource { history, keyword, categoryName }

class CategoryMatch {
  const CategoryMatch({
    required this.category,
    required this.source,
    required this.reason,
    required this.confident,
    this.alternatives = const [],
  });

  final Category category;
  final MatchSource source;

  /// e.g. 'keyword "swiggy"'.
  final String reason;

  /// False when two or more categories matched about equally well.
  final bool confident;
  final List<Category> alternatives;
}

/// Rule-based categorizer: merchant & keyword dictionary + learning from the
/// user's own past descriptions. Runs entirely on device.
class Categorizer {
  Categorizer({
    required List<Category> categories,
    List<TransactionEntry> history = const [],
  }) : _categories = categories {
    _learn(history);
  }

  final List<Category> _categories;

  /// normalized note -> categoryId -> count
  final Map<String, Map<int, int>> _noteMemory = {};

  /// Words that carry little meaning on their own; they score lower.
  static const _weakKeywords = {
    'bill',
    'fees',
    'ticket',
    'payment',
    'order',
    'shop',
    'store',
  };

  /// Keyword dictionary keyed by default category name. Multi-word phrases
  /// are matched as whole phrases and score higher than single words.
  static const Map<String, List<String>> keywords = {
    DefaultCategoryNames.food: [
      'lunch', 'dinner', 'breakfast', 'brunch', 'snack', 'snacks', 'meal',
      'restaurant', 'cafe', 'coffee', 'tea', 'chai', 'pizza', 'burger',
      'biryani', 'dosa', 'idli', 'sandwich', 'juice', 'dessert',
      'ice cream', 'bakery', 'canteen', 'mess', 'tiffin', 'food',
      'dining', 'dine', 'swiggy', 'zomato', 'dominos', 'mcdonalds',
      'kfc', 'starbucks', 'subway', 'eat', 'eating', 'takeaway',
      'restaurant bill',
    ],
    DefaultCategoryNames.groceries: [
      'grocery', 'groceries', 'vegetables', 'veggies', 'fruits', 'milk',
      'bigbasket', 'big basket', 'blinkit', 'zepto', 'instamart', 'dmart',
      'd mart', 'supermarket', 'kirana', 'rice', 'atta', 'eggs', 'bread',
      'provisions', 'jiomart',
    ],
    DefaultCategoryNames.transport: [
      'uber', 'ola', 'rapido', 'auto', 'rickshaw', 'cab', 'taxi', 'metro',
      'bus', 'petrol', 'diesel', 'fuel', 'parking', 'toll', 'fastag',
      'local train', 'bike service', 'car service', 'commute', 'ev charging',
    ],
    DefaultCategoryNames.shopping: [
      'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'clothes',
      'shirt', 'tshirt', 'shoes', 'jeans', 'dress', 'shopping', 'mall',
      'electronics', 'headphones', 'earphones', 'gadget', 'watch', 'bag',
      'furniture', 'decor', 'gift for',
    ],
    DefaultCategoryNames.bills: [
      'electricity', 'electricity bill', 'water bill', 'gas bill', 'rent',
      'wifi', 'broadband', 'internet', 'recharge', 'mobile bill',
      'phone bill', 'postpaid', 'prepaid', 'dth', 'jio', 'airtel', 'bsnl',
      'emi', 'insurance', 'maintenance', 'bill', 'utility', 'utilities',
      'cylinder', 'lpg', 'subscription',
    ],
    DefaultCategoryNames.entertainment: [
      'movie', 'movies', 'cinema', 'netflix', 'prime video', 'hotstar',
      'disney', 'spotify', 'youtube premium', 'bookmyshow', 'pvr', 'inox',
      'concert', 'gaming', 'game', 'steam', 'playstation', 'party', 'club',
      'bowling', 'outing',
    ],
    DefaultCategoryNames.health: [
      'medicine', 'medicines', 'pharmacy', 'chemist', 'doctor', 'hospital',
      'clinic', 'apollo', 'pharmeasy', '1mg', 'netmeds', 'dentist',
      'checkup', 'lab test', 'blood test', 'gym', 'fitness', 'yoga',
      'vitamins', 'physio', 'therapy',
    ],
    DefaultCategoryNames.education: [
      'course', 'udemy', 'coursera', 'books', 'book', 'tuition',
      'school fees', 'college fees', 'fees', 'exam', 'stationery',
      'coaching', 'workshop', 'certification', 'class', 'classes',
    ],
    DefaultCategoryNames.travel: [
      'flight', 'flights', 'hotel', 'irctc', 'train', 'makemytrip',
      'goibibo', 'oyo', 'airbnb', 'trip', 'holiday', 'vacation', 'resort',
      'visa', 'luggage', 'airport', 'cleartrip', 'redbus', 'bus ticket',
      'train ticket', 'tour',
    ],
    DefaultCategoryNames.salary: [
      'salary', 'payroll', 'stipend', 'paycheck', 'pay check', 'wages',
      'bonus',
    ],
    DefaultCategoryNames.freelance: [
      'freelance', 'freelancing', 'client', 'invoice', 'consulting',
      'gig', 'project payment', 'side project',
    ],
    DefaultCategoryNames.investments: [
      'dividend', 'interest', 'returns', 'mutual fund', 'stocks', 'shares',
      'profit', 'fd interest', 'sip return', 'capital gain',
    ],
    DefaultCategoryNames.gifts: [
      'gift', 'gifted', 'birthday money', 'shagun',
    ],
    DefaultCategoryNames.refunds: [
      'refund', 'refunded', 'cashback', 'cash back', 'reimbursement',
      'reimbursed', 'returned',
    ],
  };

  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _learn(List<TransactionEntry> history) {
    for (final t in history) {
      final key = normalize(t.note);
      if (key.isEmpty) continue;
      final m = _noteMemory.putIfAbsent(key, () => {});
      m[t.categoryId] = (m[t.categoryId] ?? 0) + 1;
    }
  }

  Category? _byId(int id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Category? _byName(String name, TransactionType? kind) {
    for (final c in _categories) {
      if (c.name.toLowerCase() == name.toLowerCase() &&
          (kind == null || c.kind == kind)) {
        return c;
      }
    }
    return null;
  }

  static bool _containsPhrase(String haystack, String phrase) {
    return RegExp('(^| )${RegExp.escape(phrase)}( |\$)').hasMatch(haystack);
  }

  /// Suggests a category for [text]. When [type] is given only categories of
  /// that kind are considered. Returns null when nothing matched.
  CategoryMatch? suggest(String text, {TransactionType? type}) {
    final norm = normalize(text);
    if (norm.isEmpty) return null;

    // 1. Exact description the user has used before -> their own choice.
    final memory = _noteMemory[norm];
    if (memory != null && memory.isNotEmpty) {
      final best = memory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final cat = _byId(best.first.key);
      if (cat != null && (type == null || cat.kind == type)) {
        return CategoryMatch(
          category: cat,
          source: MatchSource.history,
          reason: 'you used "${cat.name}" for this before',
          confident: true,
        );
      }
    }

    // 2. Keyword dictionary + the names of the user's own categories.
    final scores = <int, double>{};
    final reasons = <int, String>{};
    void score(Category cat, String keyword, double weight) {
      final id = cat.id;
      if (id == null) return;
      if (type != null && cat.kind != type) return;
      scores[id] = (scores[id] ?? 0) + weight;
      final prev = reasons[id];
      if (prev == null || keyword.length > prev.length) reasons[id] = keyword;
    }

    keywords.forEach((categoryName, words) {
      final cat = _byName(categoryName, null);
      if (cat == null) return;
      for (final w in words) {
        if (_containsPhrase(norm, w)) {
          final base = _weakKeywords.contains(w) ? 1.0 : 3.0;
          final wordCount = w.split(' ').length;
          score(cat, w, base * wordCount);
        }
      }
    });

    for (final cat in _categories) {
      final name = normalize(cat.name);
      if (name.length >= 3 && _containsPhrase(norm, name)) {
        score(cat, name, 4);
      }
    }

    if (scores.isEmpty) return null;
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = _byId(ranked.first.key)!;
    final confident =
        ranked.length == 1 || ranked.first.value >= ranked[1].value * 1.5;
    return CategoryMatch(
      category: top,
      source: MatchSource.keyword,
      reason: 'keyword "${reasons[top.id]}"',
      confident: confident,
      alternatives: confident
          ? const []
          : ranked
              .skip(1)
              .take(2)
              .map((e) => _byId(e.key))
              .whereType<Category>()
              .toList(),
    );
  }
}
