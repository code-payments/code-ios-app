//
//  main.swift
//  flipcash-puppet-host
//
//  The Flipcash Puppet host as a process: one JSON request per line on stdin, one response per line
//  on stdout. The orchestrator's `puppet` CLI starts it and keeps it running across behavior files,
//  sending `launch` between them.
//

import Foundation
import FlipcashPuppet

setvbuf(stdout, nil, _IOLBF, 0)
var host = FlipcashPuppetHost()
while let line = readLine() {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
    print(host.handle(line: line))
}
