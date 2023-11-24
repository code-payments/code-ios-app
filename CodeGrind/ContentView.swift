//
//  ContentView.swift
//  CodeGrind
//
//  Created by Dima Bart on 2022-03-06.
//

import SwiftUI
import CodeServices
import CodeUI

struct ContentView: View {
    
    @StateObject var grinder: Grinder
    
    @State private var selection: Selection = .prefix
    @State private var term: String = ""
    @State private var path: String = Derive.Path.solana.stringRepresentation
    
    @State private var ignoresCase: Bool = false
    
    private var matches: [Grinder.Match] {
        grinder.matches
//        (0..<25).map { _ in
//            let mnemonic = MnemonicPhrase.generate(.words12)
//            let keyPair = KeyPair(mnemonic: mnemonic, path: .solana)
//            return Grinder.Match(
//                mnemonic: mnemonic,
//                keyPair: keyPair
//            )
//        }
    }
    
    private let formatter: NumberFormatter = {
        var f = NumberFormatter()
        f.numberStyle = .decimal
        f.hasThousandSeparators = true
        return f
    }()
    
    private let base58CharacterSet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    
    // MARK: - Init -
    
    init() {
        _grinder = StateObject(wrappedValue: Grinder())
    }
    
    // MARK: - Body -
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                sidebar()
                list()
            }
            ToolsView()
        }
        .frame(minWidth: 570, minHeight: 720)
    }
    
    @ViewBuilder private func sidebar() -> some View {
        VStack(spacing: 15) {
            
            VStack(alignment: .leading) {
                Text("Search Term")
                    .font(.headline)
                Picker(selection: $selection, label: EmptyView(), content: {
                    ForEach(Selection.allCases, id: \.self) {
                        Text($0.name)
                    }
                })
                .pickerStyle(.segmented)
                
                TextField(
                    text: $term,
                    prompt: Text("Search term"),
                    label: { EmptyView() }
                )
                .font(.body)
                .padding([.leading, .trailing], 6)
                .padding([.top, .bottom], 3)
                .background(Color.white)
                .cornerRadius(5)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                .overlay {
                    if !isSearchValid() {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.textError, lineWidth: 1.0, antialiased: true)
                    }
                }
                .textFieldStyle(.plain)
                
                Toggle("Ignores Case", isOn: $ignoresCase)
            }
            .disabled(grinder.isRunning)
            
            VStack(alignment: .leading) {
                Text("Derivation Path")
                    .font(.headline)
                
                TextField(
                    text: $path,
                    prompt: Text(Derive.Path.solana.stringRepresentation),
                    label: { EmptyView() }
                )
                .textFieldStyle(.roundedBorder)
            }
            .disabled(grinder.isRunning)
            
            Spacer()
            HStack {
                Text("Count")
                Spacer()
                Text("\(grinder.totalCount)")
            }
            HStack {
                Text("Keys per hour")
                Spacer()
                Text("\(formatter.string(from: UInt64(grinder.hashRate))!)")
            }
            Button {
                grinder.reset()
            } label: {
                Text("Clear")
                    .frame(maxWidth: .infinity)
            }
            .disabled(grinder.isRunning || grinder.matches.isEmpty)
            
            Button {
                if grinder.isRunning {
                    grinder.cancel()
                } else {
                    grinder.grindMulticore(
                        term: term,
                        type: selection.matchType,
                        path: derivationPath()!,
                        ignoringCase: ignoresCase
                    )
                }
            } label: {
                Text(grinder.isRunning ? "Stop" : "Grind")
                    .frame(maxWidth: .infinity)
            }
            .disabled(derivationPath() == nil)
        }
        .padding(15)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
    }
    
    @ViewBuilder private func list() -> some View {
        List {
            ForEach(matches) { match in
                HStack {
                    Image.system(.doc)
                    Text(match.keyPair.publicKey.base58)
                        .font(.body.monospaced())
                        .fixedSize(horizontal: true, vertical: true)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(10)
                .background(Color(white: 0.96))
                .cornerRadius(8)
                .contextMenu {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(match.keyPair.publicKey.base58, forType: .string)
                    } label: {
                        Label("Copy Base58 Address", systemImage: "key.fill")
                    }
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(match.mnemonic.phrase, forType: .string)
                    } label: {
                        Label("Copy Seed Phrase", systemImage: "text.viewfinder")
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private func isSearchValid() -> Bool {
        term.first { !base58CharacterSet.contains($0) } == nil
    }
    
    // MARK: - Content -
    
    private func derivationPath() -> Derive.Path? {
        Derive.Path(path)
    }
}

struct ToolsView: View {
            
    @State private var use24: Bool  = false
    @State private var words: String = ""//"angle crystal improve volume punch tissue reopen affair spare tunnel nation forget"
    @State private var path: String = Derive.Path.solana.stringRepresentation
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 15) {
                Text("Mnemonic")
                    .font(.headline)
                TextEditor(text: $words)
                    .frame(height: 120)
                    .font(.body)
                    .padding(6)
                    .background(Color.white)
                    .cornerRadius(5)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                
                Toggle("24 words", isOn: $use24)
                
                VStack(alignment: .leading) {
                    Text("Derivation Path")
                        .font(.headline)
                    
                    TextField(
                        text: $path,
                        prompt: Text(Derive.Path.solana.stringRepresentation),
                        label: { EmptyView() }
                    )
                    .textFieldStyle(.roundedBorder)
                }
                
                Spacer()
                
                Button {
                    words = MnemonicPhrase.generate(use24 ? .words24 : .words12).phrase
                } label: {
                    Text("Generate")
                        .frame(maxWidth: .infinity)
                        .disabled(derivationPath() == nil)
                }
            }
            .padding(15)
            .frame(width: 200)
            .frame(maxHeight: .infinity)
            
            VStack(alignment: .leading, spacing: 8) {
                if let (mnemonic, derivedKey, entropy) = privateKey() {
                    Text("Info")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Type")
                                .font(.footnote)
                                .foregroundColor(.gray)
                            Text(mnemonic.kind == .words12 ? "12 Words" : "24 Words")
                                .font(.body.monospaced())
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Entropy")
                                .font(.footnote)
                                .foregroundColor(.gray)
                            Text(entropy.hexEncodedString())
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Seed")
                                .font(.footnote)

                            Text(derivedKey.keyPair.seed!.base58)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Public Key")
                                .font(.footnote)
                                .foregroundColor(.gray)
                            Text(derivedKey.keyPair.publicKey.base58)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Private Key")
                                .font(.footnote)
                                .foregroundColor(.gray)
                            Text(derivedKey.keyPair.privateKey.base58)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(15)
            .background(Color.white)
        }
        .vSeparator(color: Color(white: 0.83), position: .top)
    }
    
    // MARK: - Content -
    
    private func derivationPath() -> Derive.Path? {
        Derive.Path(path)
    }
    
    private func privateKey() -> (MnemonicPhrase, DerivedKey, Data)? {
        guard let mnemonic = MnemonicPhrase(words: words.components(separatedBy: " ")) else {
            return nil
        }
        
        guard let entropy = try? Mnemonic.toEntropy(mnemonic.words).data else {
            return nil
        }
        
        guard let path = derivationPath() else {
            return nil
        }
        
        let keyPair = KeyPair(mnemonic: mnemonic, path: path)
        let derivedKey = DerivedKey(
            path: path,
            keyPair: keyPair
        )
        
        return (mnemonic, derivedKey, entropy)
    }
}

extension NSTextView {
    open override var frame: CGRect {
        didSet {
            backgroundColor = .clear
            drawsBackground = true
        }
    }
}

extension ContentView {
    enum Selection: CaseIterable {
        
        case prefix
        case suffix
        
        var name: String {
            switch self {
            case .prefix: return "Prefix"
            case .suffix: return "Suffix"
            }
        }
        
        var matchType: Grinder.MatchType {
            switch self {
            case .prefix: return .prefix
            case .suffix: return .suffix
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
