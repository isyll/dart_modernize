// Negative: members already follow canonical order
// (fields -> constructors -> getters -> methods). Nothing to reorder.
class Account {
  final String id;
  int _balance = 0;

  Account(this.id);

  int get balance => _balance;

  void deposit(int amount) => _balance += amount;
}
