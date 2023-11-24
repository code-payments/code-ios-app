//
//  RegionSelectionScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-09.
//

import SwiftUI
import CodeUI
import CodeServices

struct RegionSelectionScreen: View {
        
    @Binding public var isPresented: Bool

    public var didSelectRegion: (Region) -> Void
    
    private let regions = Region.localizedDescriptionForAllRegions()
    
    // MARK: - Init -
    
    public init(isPresented: Binding<Bool>, didSelectRegion: @escaping (Region) -> Void) {
        self._isPresented = isPresented
        self.didSelectRegion = didSelectRegion
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                ModalHeaderBar(title: Localized.Title.selectCountry, isPresented: $isPresented)
                Spacer()
                ScrollBox(color: .backgroundMain) {
                    LazyTable(contentPadding: .scrollBox) {
                        ForEach(regions, id: \.region.rawValue) { regionDescription in
                            Button {
                                didSelectRegion(regionDescription.region)
                            } label: {
                                HStack(spacing: 15) {
                                    Flag(style: .fiat(regionDescription.region))
                                    Text(regionDescription.localizedName)
                                        .foregroundColor(.textMain)
                                        .lineLimit(1)
                                        .layoutPriority(10)
                                    Spacer()
                                    Text("+\(regionDescription.countryCode)")
                                        .foregroundColor(.textSecondary)
                                        .lineLimit(1)
                                        .layoutPriority(10)
                                }
                                .font(.appTextMedium)
                            }
                            .padding([.top, .bottom], 20)
                            .padding(.trailing, 20)
                            .vSeparator(color: .rowSeparator)
                            .padding(.leading, 20)
                        }
                    }
                }
            }
        }
        .onAppear {
            Analytics.open(screen: .regionSelection)
            ErrorReporting.breadcrumb(.regionSelectionScreen)
        }
    }
}

// MARK: - Region -

private extension Region {
    static func localizedDescriptionForAllRegions() -> [RegionDescription] {
        let formatter = PhoneFormatter()
        let descriptions: [RegionDescription] = Region.allCases.compactMap { region in
            guard let countryCode = formatter.countryCode(for: region) else {
                return nil
            }
            
            return RegionDescription(
                region: region,
                countryCode: countryCode
            )
        }
            
        return descriptions.sorted { lhs, rhs in
            lhs.localizedName.localizedCompare(rhs.localizedName) == .orderedAscending
        }
    }
}

// MARK: - RegionDescription -

private struct RegionDescription {
    
    let region: Region
    let countryCode: UInt64
    let localizedName: String
    
    init(region: Region, countryCode: UInt64) {
        self.region = region
        self.countryCode = countryCode
        self.localizedName = Locale.current.localizedString(forRegionCode: region.rawValue)!
    }
}

// MARK: - Previews -

struct RegionSelectionScreen_Previews: PreviewProvider {
    static var previews: some View {
        RegionSelectionScreen(
            isPresented: .constant(true),
            didSelectRegion: { _ in }
        )
        .environmentObjectsForSession()
    }
}
