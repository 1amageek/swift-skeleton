# tree-sitter-swift provenance

- Repository: https://github.com/alex-pinkus/tree-sitter-swift
- Upstream branch: `main`
- Commit: `28fe3a8a85586aa297524fe6164140b9521dcaff`
- Parser ABI: 14

The generated parser includes one local grammar extension before generation:

```javascript
seq("hasFeature", "(", $.simple_identifier, ")")
```

This alternative is added to `_compilation_condition` so Swift feature conditions such as `#if hasFeature(...)` parse as directives. The local grammar also changes the end of `enum_entry` from `optional(";")` to `optional($._semi)` so an automatic semicolon can precede a conditional-compilation directive between enum cases. Upstream `main` supplies typed-throws support. The vendored `parser.c`, `scanner.c`, and `tree_sitter/parser.h` files are generated with Tree-sitter CLI 0.25.10. The upstream MIT license is preserved in `LICENSE`.
