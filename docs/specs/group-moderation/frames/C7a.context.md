# C7a · C7a · Group overflow (host)

- Frame: `C7a · Group overflow (host)`
- Node id: `12766:268`
- Size: 402x874
- Screenshot: `C7a.png`
- Caption: Host-only Moderation submenu in the group overflow. Members never see it. iOS: a nested Menu, drawn natively. Android: Material 3 has no submenu, so the DropdownMenu swaps its items in place, with a back row.

Coordinates are `@x,y WxH` in frame pixels (points on iOS, dp on Android) relative to the frame's top-left. `AL=V|H` is auto-layout direction; `pad` is top/right/bottom/left. `{name}` is a bound Figma variable (see tokens.md). Text rows list style name, or weight+size when no style is bound. The base screen is an instance of a shared base component and is not described beyond its name.

## Layers
```
Base: [Base / iOS · Group profile (Jeffy)] @0,0 402x874
UIMenu [12766:270] @140,60 248x196 fill=#3d3d40@0.96 r=26 AL=V pad=6/0/6/0 fx=BACKGROUND_BLUR,DROP_SHADOW
  Row Encryption         @140,66  248x44 icon lock.open            "Encryption" fill={textMain}
  Row Mute Notifications @140,110 248x44 icon bell.slash          "Mute Notifications" fill={textMain}
  Row Moderation (NEW) [12768:186] @140,154 248x44 AL=H gap=16 pad=0/20/0/20
    icon shield 24x24 @160,164; "Moderation" Regular 17 fill={textMain} @200,166; trailing chevron.right 14x14 @354,169 (glyph 4x8, opacity 0.60)
  Separator              @140,198 248x8
  Row Report             @140,206 248x44 icon exclamationmark.bubble "Report" fill={Red}
```
