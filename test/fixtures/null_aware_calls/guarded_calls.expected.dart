class Controller {
  void dispose() {}
  Future<void> close() async {}
}

class Widget {
  const Widget(this.onTap);

  final void Function()? onTap;
}

class View {
  View(this.widget, this.controller);

  final Widget widget;
  final Controller? controller;

  void tap() {
    widget.onTap?.call();
  }

  void release() {
    controller?.dispose();
  }
}

void notify(void Function(int)? onChanged, int value) {
  onChanged?.call(value);
}

void notifyBang(void Function(int)? onChanged, int value) {
  onChanged?.call(value);
}

Future<void> shutdown(Controller? controller) async {
  await controller?.close();
  controller?.dispose();
}
