clear classes

d = DynamicClassExample;
d = d.store('hello', 1023);

assert(d.hello == 1023);
assert(d.gethello() == 1023);
assert(d(1) == 1023);
assert(strcmp(d{1}, 'hello'));

