// `__` is still a name a body can read, and a named parameter's name is part
// of its function's API.
int twice(int __) => __ * 2;

void configure({int __ = 0}) => print(__);

void report(Object error, StackTrace __) => print('$error $__');
