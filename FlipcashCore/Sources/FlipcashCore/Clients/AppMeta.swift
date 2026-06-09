//
//  AppMeta.swift
//  FlipcashCore
//

import Foundation

public enum AppMeta {
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    }

    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    }
}
