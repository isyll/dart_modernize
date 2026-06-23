class BankAccount {
  String owner = '';
  int balance = 0;
  bool frozen = false;

  void deposit(int amount) {
    balance += amount;
  }

  void freeze() {
    frozen = true;
  }
}

BankAccount open() {
  var account = BankAccount()
    ..owner = 'Ibrahima'
    ..deposit(1000)
    ..deposit(500)
    ..freeze();
  return account;
}
