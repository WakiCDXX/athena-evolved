import collections
class array:
    def __init__(self, data=None, *args, **kwargs):
        self.data = data if data is not None else []
    def __getitem__(self, key):
        return self.data[key]
    def __setitem__(self, key, value):
        self.data[key] = value
    def __len__(self):
        return len(self.data)
    def sum(self, *args, **kwargs):
        return sum(self.data)
    def mean(self, *args, **kwargs):
        return sum(self.data) / len(self.data) if self.data else 0
def zeros(shape, *args, **kwargs):
    return array([0] * (shape[0] if isinstance(shape, (list, tuple)) else shape))
def sum(*args, **kwargs):
    return sum(args[0]) if args else 0
