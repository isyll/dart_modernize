class Event {
  const Event();
}

void dispatch(Event e) {}

void main() {
  dispatch(.new());
}
