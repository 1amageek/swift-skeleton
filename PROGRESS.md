# Progress

- [x] C1 Index scope parity (f5c90bb) `depends:none` `parallel:none`
- [x] C2 SwiftPM manifest resolution without the `.build` lock (7b67640) `depends:C1` `parallel:none`
- [x] C3 AST evidence classification, linear method lookup, external writes (8a0f113) `depends:C2` `parallel:none`
- [x] C4 Declaration end lines and block impl markers (970754f) `depends:C3` `parallel:none`
- [x] C5 CLI / Daemon / Sidecar failure contracts (2bc8d72) `depends:C4` `parallel:none`
- [x] P1 Tier1 parsers (1faeb4f) `depends:none` `parallel:none`
- [x] P2 Go and Zig parsers (280b505) `depends:none` `parallel:none`
- [x] P3 Java and Python parsers (c7eb1da) `depends:none` `parallel:none`
- [x] P4 C++ parser (54aa04d) `depends:none` `parallel:none`
- [x] V Integration: full debug suite, release build, release E2E and client tests `depends:C1,C2,C3,C4,C5,P1,P2,P3,P4` `parallel:none`
