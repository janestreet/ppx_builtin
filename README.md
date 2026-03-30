ppx_builtin
===========

`ppx_builtin` processes `[@@builtin]` attributes on external declarations based
on the current architecture.

- `[@@builtin amd64]` is erased on arm64.
- `[@@builtin arm64]` is erased on amd64.
- `[@@builtin amd64 arm64]` is kept on both architectures.
- `[@@builtin]` (no architectures) is always kept.


Note that in all cases, the external declaration remains; only the `[@@builtin]`
attribute may be removed. The corresponding C symbol(s) still need to be provided.

## Replacing Symbols

You can specify different native code symbols for different architectures:

```ocaml
external foo : int -> int = "bytecode_sym" "native_sym"
[@@builtin (amd64, "amd64_sym") (arm64, "arm64_sym")]
```

On amd64, this becomes:
```ocaml
external foo : int -> int = "bytecode_sym" "amd64_sym"
[@@builtin]
```

On arm64, this becomes:
```ocaml
external foo : int -> int = "bytecode_sym" "arm64_sym"
[@@builtin]
```

The default native symbol will be preserved on any unspecified architectures.
