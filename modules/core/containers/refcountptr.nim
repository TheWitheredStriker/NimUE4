# Copyright 2016 Xored Software, Inc.

type
  TRefCountPtr* {.header: "Templates/RefCounting.h", importcpp.} [out T] = object

# TODO
