//
//  SwipeLens.metal
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The swipe control's lens: inside a capsule (a circle when `halfLength` is 0), a band just within the rim samples the layer from
// nearer the centre, so whatever passes under the rim stretches outward and bends with it. The
// pull is strongest at the rim and eases to nothing `band` points in; the middle is left alone.
//
// `bounds` is the layer's rect (SwiftUI's `.boundingRect`), so the lens sits on its vertical middle.
// `halfLength` is how far the capsule's straight run reaches either side of `centerX`.
[[ stitchable ]] half4 swipeLens(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds,
    float centerX,
    float radius,
    float halfLength,
    float bend,
    float band
) {
    float centerY = bounds.y + bounds.w * 0.5;
    // The nearest point on the capsule's spine, so the rim keeps one distance all the way round.
    float2 center = float2(centerX + clamp(position.x - centerX, -halfLength, halfLength), centerY);
    float2 fromCenter = position - center;
    float distance = length(fromCenter);

    if (radius <= 0.0 || distance >= radius || distance < 0.001) {
        return layer.sample(position);
    }

    float insideRim = radius - distance;
    float pull = 1.0 - smoothstep(0.0, max(band, 0.001), insideRim);
    float2 outward = fromCenter / distance;
    return layer.sample(position - outward * bend * pull * pull);
}
