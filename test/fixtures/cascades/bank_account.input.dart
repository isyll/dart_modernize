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
  var account = BankAccount();
  account.owner = 'Ibrahima';
  account.deposit(1000);
  account.deposit(500);
  account.freeze();
  return account;
}
