class Icon {
  const Icon._(this.data, {this.color, this.size});

  final int data;
  final int? color;
  final int? size;
}

class AddToList extends Icon {
  const AddToList._count({required int data, int? color, int? size})
    : super._(data, color: color, size: size);
}

class Plain extends Icon {
  const Plain({int? color, int? size}) : super._(0, color: color, size: size);
}
