// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "liyun6666/moon-ipp"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/liyun6666/moon-ipp"

license = "Apache-2.0"

keywords = [ "ipp", "printing", "protocol", "cups", "client" ]

preferred_target = "native"

description = "MoonBit-native IPP codec, capability validation and network printing client"

import {
  "moonbitlang/async@0.22.4",
}
