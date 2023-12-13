################################################################################
# This is a variant of the FirebaseError object that I made because I can't
# return OK if the return type is Object. This has no properties and does NOT
# inherit from FirebaseError intentionally so that the check
# `result is FirebaseError` or something like that still works. -- Haley
# This has no properties or methods :P
################################################################################
@icon("icon.svg")
extends RefCounted
class_name FirebaseOk
