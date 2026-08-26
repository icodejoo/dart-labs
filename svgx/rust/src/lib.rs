pub mod api;
mod frb_generated;

// Test-only parsing benchmark; see src/bench.rs for the run command.
// 仅测试期的解析基准；运行命令见 src/bench.rs。
#[cfg(test)]
mod bench;
