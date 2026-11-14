import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/database/default_categories.dart';
import 'package:pennywise/models/category.dart';
import 'package:pennywise/models/transaction_entry.dart';
import 'package:pennywise/services/smart/categorizer.dart';
import 'package:pennywise/services/smart/transaction_parser.dart';

List<Category> _categories() {
  var id = 1;
  return [for (final c in buildDefaultCategories()) c.copyWith(id: id++)];
}

void main() {
  // Friday 6 Nov 2026, 3 pm.
  final now = DateTime(2026, 11, 6, 15);
  late TransactionParser parser;

  setUp(() {
    parser = TransactionParser(Categorizer(categories: _categories()));
  });

  ParsedTransaction p(String s) => parser.parse(s, now: now);

  test('the example from the spec', () {
    final r = p('I spent 250 rupees on lunch');
    expect(r.amountMinor, 25000);
    expect(r.type, TransactionType.expense);
    expect(r.category?.name, DefaultCategoryNames.food);
    expect(r.description, 'Lunch');
    expect(r.issues, isEmpty);
    expect(r.isComplete, isTrue);
  });

  test('income with salary keyword', () {
    final r = p('got salary 50000');
    expect(r.amountMinor, 5000000);
    expect(r.type, TransactionType.income);
    expect(r.category?.name, DefaultCategoryNames.salary);
  });

  test('merchant + relative date', () {
    final r = p('uber 180 yesterday');
    expect(r.amountMinor, 18000);
    expect(r.type, TransactionType.expense);
    expect(r.category?.name, DefaultCategoryNames.transport);
    expect(r.date, DateTime(2026, 11, 5));
    expect(r.dateDetected, isTrue);
    expect(r.description, 'Uber');
  });

  test('commas, payment method and multi-word keywords', () {
    final r = p('paid 1,200 for electricity bill via upi');
    expect(r.amountMinor, 120000);
    expect(r.category?.name, DefaultCategoryNames.bills);
    expect(r.paymentMethod, PaymentMethod.upi);
    expect(r.description, 'Electricity bill');
  });

  test('k shorthand and gpay', () {
    final r = p('spent 2k on shopping at myntra via gpay');
    expect(r.amountMinor, 200000);
    expect(r.category?.name, DefaultCategoryNames.shopping);
    expect(r.paymentMethod, PaymentMethod.upi);
    expect(r.description, 'Shopping at myntra');
  });

  test('decimal k and credit card', () {
    final r = p('dinner with friends 1.5k credit card');
    expect(r.amountMinor, 150000);
    expect(r.paymentMethod, PaymentMethod.creditCard);
    expect(r.description, 'Dinner with friends');
  });

  test('two amounts is ambiguous: asks instead of guessing', () {
    final r = p('lunch 250 and coffee 80');
    expect(r.amountMinor, isNull);
    expect(r.amountCandidates, containsAll([25000, 8000]));
    expect(r.hasIssue(ParseField.amount), isTrue);
    expect(r.isComplete, isFalse);
  });

  test('quantities are not mistaken for amounts', () {
    final r = p('2 kg rice 120');
    expect(r.amountMinor, 12000);
    expect(r.category?.name, DefaultCategoryNames.groceries);
  });

  test('a bare number asks for type and category', () {
    final r = p('500');
    expect(r.amountMinor, 50000);
    expect(r.type, isNull);
    expect(r.category, isNull);
    expect(r.hasIssue(ParseField.type), isTrue);
    expect(r.hasIssue(ParseField.category), isTrue);
  });

  test('weekday and explicit dates', () {
    expect(p('₹450 movie tickets last saturday').date, DateTime(2026, 10, 31));
    expect(p('lunch on monday 120').date, DateTime(2026, 11, 2));
    expect(p('swiggy order 349 on 3 nov').date, DateTime(2026, 11, 3));
    expect(p('paid rent 15000 on 01/11').date, DateTime(2026, 11, 1));
    expect(p('petrol 1500 day before yesterday').date, DateTime(2026, 11, 4));
    expect(p('metro 40 3 days ago').date, DateTime(2026, 11, 3));
  });

  test('a date without a year never lands in the future', () {
    final r = p('electricity 1400 on 7 dec');
    expect(r.date, DateTime(2025, 12, 7));
  });

  test('refund and cashback are income, cash back is not cash payment', () {
    final refund = p('refund 799 from amazon');
    expect(refund.type, TransactionType.income);
    expect(refund.category?.name, DefaultCategoryNames.refunds);
    final cb = p('cash back 50');
    expect(cb.type, TransactionType.income);
    expect(cb.paymentMethod, isNull);
  });

  test('"got paid" is income even though it contains "paid"', () {
    final r = p('got paid 3000 for freelance logo');
    expect(r.type, TransactionType.income);
    expect(r.category?.name, DefaultCategoryNames.freelance);
  });

  test('"1mg" (pharmacy) is not read as an amount', () {
    final r = p('1mg medicines 450');
    expect(r.amountMinor, 45000);
    expect(r.category?.name, DefaultCategoryNames.health);
  });

  test('two plausible categories of the same kind: type known, asks category',
      () {
    final r = p('metro card recharge 200');
    expect(r.type, TransactionType.expense);
    expect(r.category, isNull);
    expect(r.categoryAlternatives.length, greaterThanOrEqualTo(2));
  });

  test('income from a person keeps the name in the description', () {
    final r = p('received 500 from Rahul');
    expect(r.type, TransactionType.income);
    expect(r.description, 'From Rahul');
  });

  test('empty-ish input', () {
    final r = p('lunch');
    expect(r.amountMinor, isNull);
    expect(r.hasIssue(ParseField.amount), isTrue);
  });
}
