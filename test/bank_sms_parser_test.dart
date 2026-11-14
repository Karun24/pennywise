import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/models/transaction_entry.dart';
import 'package:pennywise/services/bank_sms_parser.dart';

void main() {
  const parser = BankSmsParser();

  group('BankSmsParser', () {
    test('parses HDFC bank card spend at merchant', () {
      const sms =
          'Rs 2,500.00 spent on your HDFC Bank Card ending 9876 at AMAZON INDIA on 10-NOV-26. Avl bal: Rs 45,210.00.';
      final result = parser.parse(sms);

      expect(result, isNotNull);
      expect(result!.amountMinor, 250000);
      expect(result.type, TransactionType.expense);
      expect(result.accountDigits, '9876');
      expect(result.merchant.toLowerCase(), contains('amazon'));
      expect(result.suggestedCategory, 'Shopping');
      expect(result.balanceMinor, 4521000);
    });

    test('parses SBI UPI debit for food delivery', () {
      const sms =
          'Dear SBI User, your A/C 1234-debited by Rs 450.00 on 12Nov26 to Swiggy UPI Ref 432109876543.';
      final result = parser.parse(sms);

      expect(result, isNotNull);
      expect(result!.amountMinor, 45000);
      expect(result.type, TransactionType.expense);
      expect(result.accountDigits, '1234');
      expect(result.merchant.toLowerCase(), contains('swiggy'));
      expect(result.suggestedCategory, 'Food & Dining');
      expect(result.referenceId, '432109876543');
    });

    test('parses ICICI salary credit / income', () {
      const sms =
          'ICICI Bank: Acct XX456 credited with INR 35,000.00 on 01-Nov-26 by NEFT-SALARY. Available Balance: INR 52,100.';
      final result = parser.parse(sms);

      expect(result, isNotNull);
      expect(result!.amountMinor, 3500000);
      expect(result.type, TransactionType.income);
      expect(result.accountDigits, '456');
      expect(result.balanceMinor, 5210000);
    });

    test('parses ATM cash withdrawal', () {
      const sms =
          'A/c *5678 debited for Rs.1,500.00 on 14-Nov-26. Info: ATM WDL CASH. Bal: Rs.8,200.00';
      final result = parser.parse(sms);

      expect(result, isNotNull);
      expect(result!.amountMinor, 150000);
      expect(result.type, TransactionType.expense);
      expect(result.accountDigits, '5678');
      expect(result.balanceMinor, 820000);
    });

    test('parses UPI payment to local vendor', () {
      const sms =
          'Paid Rs.80.00 to Chai Point using Paytm UPI. UPI Ref: 334455667788.';
      final result = parser.parse(sms);

      expect(result, isNotNull);
      expect(result!.amountMinor, 8000);
      expect(result.type, TransactionType.expense);
      expect(result.merchant.toLowerCase(), contains('chai'));
      expect(result.suggestedCategory, 'Food & Dining');
      expect(result.referenceId, '334455667788');
    });

    test('ignores non-transaction messages like OTP or promos', () {
      const otpSms =
          'Your OTP for login to Bank is 482910. Do not share this OTP with anyone.';
      expect(parser.parse(otpSms), isNull);

      const promoSms =
          'Get flat 50% discount on your next pizza order today! Use code PIZZA50.';
      expect(parser.parse(promoSms), isNull);
    });
  });
}
