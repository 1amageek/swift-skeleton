import SkeletonIndexCore
import SkeletonSwiftParser

#if kotlin
import SkeletonKotlinParser
#endif
#if typescript
import SkeletonTypeScriptParser
#endif
#if go
import SkeletonGoParser
#endif
#if zig
import SkeletonZigParser
#endif
#if rust
import SkeletonRustParser
#endif
#if cpp
import SkeletonCppParser
#endif
#if python
import SkeletonPythonParser
#endif
#if java
import SkeletonJavaParser
#endif

func allParsers() -> [any SkeletonParser] {
    var parsers: [any SkeletonParser] = [SwiftSkeletonParser()]
    #if kotlin
    parsers.append(KotlinSkeletonParser())
    #endif
    #if typescript
    parsers.append(TypeScriptSkeletonParser())
    #endif
    #if go
    parsers.append(GoSkeletonParser())
    #endif
    #if zig
    parsers.append(ZigSkeletonParser())
    #endif
    #if rust
    parsers.append(RustSkeletonParser())
    #endif
    #if cpp
    parsers.append(CppSkeletonParser())
    #endif
    #if python
    parsers.append(PythonSkeletonParser())
    #endif
    #if java
    parsers.append(JavaSkeletonParser())
    #endif
    return parsers
}
