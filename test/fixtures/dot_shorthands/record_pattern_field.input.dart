enum Suit { hearts, spades }

String describe((Suit, int) card) => switch (card) {
  (Suit.hearts, final n) => 'hearts $n',
  (_, final n) => 'other $n',
};
