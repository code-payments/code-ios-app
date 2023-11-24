//
//  CurrencyCode.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum CurrencyCode: String, CaseIterable, Codable, Equatable, Hashable {
    
    // Crypto
    
    case kin
    
    // Fiat
    
    case aed
    case afn
    case all
    case amd
    case ang
    case aoa
    case ars
    case aud
    case awg
    case azn
    case bam
    case bbd
    case bdt
    case bgn
    case bhd
    case bif
    case bmd
    case bnd
    case bob
    case brl
    case bsd
    case btn
    case bwp
    case byn
    case bzd
    case cad
    case cdf
    case chf
    case clp
    case cny
    case cop
    case crc
    case cup
    case cve
    case czk
    case djf
    case dkk
    case dop
    case dzd
    case egp
    case ern
    case etb
    case eur
    case fjd
    case fkp
    case gbp
    case gel
    case ghs
    case gip
    case gmd
    case gnf
    case gtq
    case gyd
    case hkd
    case hnl
    case hrk
    case htg
    case huf
    case idr
    case ils
    case inr
    case iqd
    case irr
    case isk
    case jmd
    case jod
    case jpy
    case kes
    case kgs
    case khr
    case kmf
    case kpw
    case krw
    case kwd
    case kyd
    case kzt
    case lak
    case lbp
    case lkr
    case lrd
    case lyd
    case mad
    case mdl
    case mga
    case mkd
    case mmk
    case mnt
    case mop
    case mru
    case mur
    case mvr
    case mwk
    case mxn
    case myr
    case mzn
    case nad
    case ngn
    case nio
    case nok
    case npr
    case nzd
    case omr
    case pab
    case pen
    case pgk
    case php
    case pkr
    case pln
    case pyg
    case qar
    case ron
    case rsd
    case rub
    case rwf
    case sar
    case sbd
    case scr
    case sdg
    case sek
    case sgd
    case shp
    case sll
    case sos
    case srd
    case ssp
    case stn
    case syp
    case szl
    case thb
    case tjs
    case tmt
    case tnd
    case top
    case `try`
    case ttd
    case twd
    case tzs
    case uah
    case ugx
    case usd
    case uyu
    case uzs
    case ves
    case vnd
    case vuv
    case wst
    case xaf
    case xcd
    case xof
    case xpf
    case yer
    case zar
    case zmw
    case sle
    case ved
    
    public var overrideCurrencySymbol: String? {
        switch self {
        case .kin:
            return ""
        default:
            return nil
        }
    }
    
    // MARK: - Init -
    
    public init?(currencyCode: String) {
        self.init(rawValue: currencyCode.lowercased())
    }
    
    // MARK: - Local -
    
    public static func local() -> CurrencyCode? {
        guard let currencyCode = Locale.current.currencyCode else {
            return nil
        }
        
        return CurrencyCode.allCases.first { $0 == currencyCode }
    }
    
    // MARK: - Equatable -
    
    public static func ==(lhs: CurrencyCode, rhs: String) -> Bool {
        lhs.rawValue == rhs.lowercased()
    }
    
    public static func ==(lhs: String, rhs: CurrencyCode) -> Bool {
        lhs.lowercased() == rhs.rawValue
    }
}

extension CurrencyCode {
    
    private static let lookupTable: [CurrencyCode: Set<String>] = {
        var container: [CurrencyCode: Set<String>] = [:]
        Locale.availableIdentifiers.forEach {
            let locale = Locale(identifier: $0)
            
            guard
                let currencyCode = locale.currencyCode,
                let currency = CurrencyCode(currencyCode: currencyCode),
                let symbol = locale.currencySymbol
            else {
                return
            }
            
            if var set = container[currency] {
                set.insert(symbol)
                container[currency] = set
            } else {
                container[currency] = [symbol]
            }
        }
        return container
    }()
    
    public var currencySymbols: [String] {
        (CurrencyCode.lookupTable[self] ?? []).sorted { lhs, rhs in
            lhs.count < rhs.count
        }
    }
    
    public var singleCharacterCurrencySymbols: String? {
        (CurrencyCode.lookupTable[self] ?? []).first { $0.count == 1 }
    }
}

// MARK: - Identifiable -

extension CurrencyCode: Identifiable {
    public var id: String {
        rawValue
    }
}

// MARK: - Index -

extension CurrencyCode {
    public var index: Byte {
        Byte(CurrencyCode.allCases.firstIndex(of: self)!)
    }
    
    public init?(index: Byte) {
        self = CurrencyCode.allCases[Int(index)]
    }
}

// MARK: - Region -

extension CurrencyCode {
    
    public static func allCurrencies(in locale: Locale) -> [CurrencyDescription] {
        Self
            .allCases
            .compactMap {
                guard let name = $0.localizedName(in: locale) else {
                    return nil
                }
                
                return CurrencyDescription(
                    currency: $0,
                    localizedName: name
                )
            }
            .sortedLocalizedAlphabetically()
    }
    
    public func localizedName(in locale: Locale) -> String? {
        switch self {
        case .kin:
            return "Kin"
        default:
            return locale.localizedString(forCurrencyCode: rawValue)
        }
    }
    
    public var region: Region? {
        switch self {
            
        // Crypto
                   
        case .kin: return nil
            
        // Fiat
            
        case .usd: return .us
        case .eur: return .eu
        case .chf: return .ch
        case .nzd: return .nz
        case .xcd: return .ag
        case .zar: return .za
        case .dkk: return .dk
        case .gbp: return .gb
        case .ang: return .cw
        case .xpf: return .pf
        case .mad: return .ma
        case .xaf: return nil
        case .aud: return .au
        case .nok: return .no
        case .ils: return .il
        case .xof: return nil
        case .bdt: return .bd
        case .gtq: return .gt
        case .gyd: return .gy
        case .afn: return .af
        case .kyd: return .ky
        case .bbd: return .bb
        case .kes: return .ke
        case .mvr: return .mv
        case .egp: return .eg
        case .crc: return .cr
        case .hrk: return .hr
        case .sgd: return .sg
        case .brl: return .br
        case .kgs: return .kg
        case .ssp: return .ss
        case .btn: return .bt
        case .pkr: return .pk
        case .mmk: return .mm
        case .mru: return .mr
        case .uzs: return .uz
        case .stn: return .st
        case .lyd: return .ly
        case .mzn: return .mz
        case .sle: return .sl
        case .sll: return .sl
        case .tjs: return .tj
        case .hkd: return .hk
        case .shp: return .sh
        case .mxn: return .mx
        case .wst: return .ws
        case .bob: return .bo
        case .idr: return .id
        case .cdf: return .cd
        case .bsd: return .bs
        case .bmd: return .bm
        case .huf: return .hu
        case .azn: return .az
        case .pab: return .pa
        case .kzt: return .kz
        case .cop: return .co
        case .rub: return .ru
        case .qar: return .qa
        case .cup: return .cu
        case .amd: return .am
        case .top: return .to
        case .sar: return .sa
        case .kpw: return .kp
        case .nio: return .ni
        case .aoa: return .ao
        case .isk: return .is
        case .mnt: return .mn
        case .mga: return .mg
        case .thb: return .th
        case .byn: return .by
        case .bwp: return .bw
        case .rsd: return .rs
        case .clp: return .cl
        case .gmd: return .gm
        case .aed: return .ae
        case .tzs: return .tz
        case .all: return .al
        case .khr: return .kh
        case .irr: return .ir
        case .etb: return .et
        case .php: return .ph
        case .mdl: return .md
        case .sbd: return .sb
        case .sdg: return .sd
        case .vuv: return .vu
        case .mkd: return .mk
        case .htg: return .ht
        case .srd: return .sr
        case .bzd: return .bz
        case .bif: return .bi
        case .myr: return .my
        case .pen: return .pe
        case .bhd: return .bh
        case .ron: return .ro
        case .uah: return .ua
        case .pyg: return .py
        case .ttd: return .tt
        case .cad: return .ca
        case .scr: return .sc
        case .try: return .tr
        case .ved: return .ve
        case .ves: return .ve
        case .fkp: return .fk
        case .hnl: return .hn
        case .gnf: return .gn
        case .ngn: return .ng
        case .mwk: return .mw
        case .ern: return .er
        case .szl: return .sz
        case .bgn: return .bg
        case .mop: return .mo
        case .sek: return .se
        case .bnd: return .bn
        case .fjd: return .fj
        case .kwd: return .kw
        case .czk: return .cz
        case .twd: return .tw
        case .dop: return .do
        case .djf: return .dj
        case .jpy: return .jp
        case .omr: return .om
        case .lrd: return .lr
        case .kmf: return .km
        case .mur: return .mu
        case .jmd: return .jm
        case .tnd: return .tn
        case .lbp: return .lb
        case .tmt: return .tm
        case .jod: return .jo
        case .lkr: return .lk
        case .ugx: return .ug
        case .sos: return .so
        case .nad: return .na
        case .pln: return .pl
        case .awg: return .aw
        case .rwf: return .rw
        case .lak: return .la
        case .dzd: return .dz
        case .yer: return .ye
        case .syp: return .sy
        case .uyu: return .uy
        case .cny: return .cn
        case .krw: return .kr
        case .ars: return .ar
        case .ghs: return .gh
        case .npr: return .np
        case .inr: return .in
        case .iqd: return .iq
        case .bam: return .ba
        case .cve: return .cv
        case .gel: return .ge
        case .zmw: return .zm
        case .gip: return .gi
        case .vnd: return .vn
        case .pgk: return .pg
        }
    }
}

// MARK: - CurrencyDescription -

public struct CurrencyDescription: Codable, Equatable, Hashable {
    
    public let currency: CurrencyCode
    public let localizedName: String
    
    init(currency: CurrencyCode, localizedName: String) {
        self.currency = currency
        self.localizedName = localizedName
    }
}

extension Array where Element == CurrencyDescription {
    public func sortedLocalizedAlphabetically() -> [Element] {
        sorted { lhs, rhs in
            lhs.localizedName.localizedCompare(rhs.localizedName) == .orderedAscending
        }
    }
}

// MARK: - Identifiable -

extension CurrencyDescription: Identifiable {
    public var id: String {
        currency.rawValue
    }
}
