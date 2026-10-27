# C7b · C7b · Moderation submenu open

- Frame: `C7b · Moderation submenu open`
- Node id: `12768:192`
- Size: 402x874
- Screenshot: `C7b.png`
- Caption: The submenu opens in place. Silenced and Removed each open their own list, filtered client-side from one GetRestrictedUsers page.

Coordinates are `@x,y WxH` in frame pixels (points on iOS, dp on Android) relative to the frame's top-left. `AL=V|H` is auto-layout direction; `pad` is top/right/bottom/left. `{name}` is a bound Figma variable (see tokens.md). Text rows list style name, or weight+size when no style is bound. The base screen is an instance of a shared base component and is not described beyond its name.

## Layers
```
Base: [Base / iOS · Group profile (Jeffy)] @0,0 402x874
UIMenu [12768:193] @140,60 248x152 fill=#3d3d40@0.96 r=26 AL=V pad=6/0/6/0 fx=BACKGROUND_BLUR,DROP_SHADOW
  Header row "Moderation" [12768:221] @140,66 248x44: icon shield @160,76; title Semi Bold 17 fill={textMain} @200,78; trailing chevron.down 14x14 @354,81 (glyph 8x4, opacity 0.60)  -- expanded state; the chevron points down instead of right
  Separator @140,110 248x8
  Row Silenced @140,118 248x44 icon speaker.slash        "Silenced" Regular 17 fill={textMain}
  Row Removed  @140,162 248x44 icon person.badge.minus   "Removed"  Regular 17 fill={textMain}
```
