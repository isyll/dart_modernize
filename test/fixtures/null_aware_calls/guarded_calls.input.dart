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
    if (widget.onTap != null) {
      widget.onTap!();
    }
  }

  void release() {
    if (controller != null) controller!.dispose();
  }
}

void notify(void Function(int)? onChanged, int value) {
  if (onChanged != null) onChanged(value);
}

void notifyBang(void Function(int)? onChanged, int value) {
  if (onChanged != null) onChanged!(value);
}

Future<void> shutdown(Controller? controller) async {
  if (controller != null) await controller.close();
  if (null != controller) controller.dispose();
}
