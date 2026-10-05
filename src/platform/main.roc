platform ""
    requires {} { main! : List(Str) => Try({}, [Exit(I32), ..]) }
    exposes [Stdout, Stderr, Stdin]
    packages { roc: "nightly-2026-10-04-130536d" }
    provides { "roc_main": main_for_host! }
    hosted {
        "roc_stderr_line": Host.stderr_line!,
        "roc_stdin_line": Host.stdin_line!,
        "roc_stdout_line": Host.stdout_line!,
    }
    targets: {
        x64mac: { inputs: [app], output: Archive },
        arm64mac: { inputs: [app], output: Archive },
        x64musl: { inputs: [app], output: Archive },
        x64v1musl: { inputs: [app], output: Archive },
        arm64musl: { inputs: [app], output: Archive },
        arm64v1musl: { inputs: [app], output: Archive },
        x64win: { inputs: [app], output: Archive },
    }

import Stdout
import Stderr
import Stdin
import Host

main_for_host! : List(Str) => I32
main_for_host! = |args| {
    result = main!(args)
    match result {
        Ok({}) => 0
        Err(Exit(code)) => code
        Err(other) => {
            _ = Stderr.line!("ERROR: ${Str.inspect(other)}")
            -1
        }
    }
}
