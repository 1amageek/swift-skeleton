# Progress

- [x] C1 Index scope parity: root-relative exclusions, update() honors open-time scope, context findings rebuilt without stale wire/dead `depends:none` `parallel:none`
- [x] C2 SwiftPM manifest resolution independent of the package `.build` lock `depends:C1` `parallel:none`
- [x] C3 AST evidence: explicit method node classification, linear method lookup, non-local writes count as observable work `depends:C2` `parallel:none`
- [x] C4 Rendering: Swift declaration end lines, block impl markers from visible members and owned methods `depends:C3` `parallel:none`
- [ ] C5 CLI / Daemon / Sidecar: user errors exit cleanly, JSON-RPC 2.0 compliance, Sidecar failure parity, remove unused IndexCache `depends:C4` `parallel:none`
- [ ] P1 Tier1 parsers (Kotlin / TypeScript / Rust + DeclarationExtractor / TextUtilities) defects `depends:none` `parallel:none`
- [ ] P2 Go and Zig parser defects `depends:none` `parallel:none`
- [ ] P3 Java and Python parser defects `depends:none` `parallel:none`
- [ ] P4 C++ parser defects `depends:none` `parallel:none`
- [ ] V Integrate parser branches, full test suite, E2E CLI check `depends:C1,C2,C3,C4,C5,P1,P2,P3,P4` `parallel:none`
