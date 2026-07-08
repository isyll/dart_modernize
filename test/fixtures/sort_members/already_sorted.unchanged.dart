// Negative: members already follow canonical order
// (constructors -> fields -> getters -> methods). Nothing to reorder.
class Account {
  Account(this.id);

  final String id;
  int _balance = 0;

  int get balance => _balance;

  void deposit(int amount) => _balance += amount;
}
