import os


def add(a, b=2, *rest):
    """Doc."""
    total = a + b
    for x in rest:
        total += x
    return total


class Box:
    def size(self, w, h):
        return w * h


x = add(1, 2)
