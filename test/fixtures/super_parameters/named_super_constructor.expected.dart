class Icon {
  const Icon._(this.data, {this.color, this.size});

  final int data;
  final int? color;
  final int? size;
}

class AddToList extends Icon {
  const AddToList._count({required int data, super.color, super.size})
    : super._(data);
}

class Plain extends Icon {
  const Plain({super.color, super.size}) : super._(0);
}
