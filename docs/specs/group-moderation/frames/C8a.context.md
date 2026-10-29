# C8a · C8a · Silenced list

- Frame: `C8a · Silenced list`
- Node id: `12766:319`
- Size: 402x874
- Screenshot: `C8a.png`
- Caption: Silenced members from GetRestrictedUsers. A timed row counts down on the client, because a silence ends with no event.

Coordinates are `@x,y WxH` in frame pixels (points on iOS, dp on Android) relative to the frame's top-left. `AL=V|H` is auto-layout direction; `pad` is top/right/bottom/left. `{name}` is a bound Figma variable (see tokens.md). Text rows list style name, or weight+size when no style is bound. The base screen is an instance of a shared base component and is not described beyond its name.

## Layers
```
Screen bg {backgroundMain}; no base instance (full screen)
Nav: back Ellipse @16,60 40x40 fill=#ffffff@0.12 + chevron.left 20x20 @25,70; title "Silenced" Semi Bold 16 (no style) fill={textMain} @168,70 67x19 (centered)
Status Bar - iPhone @0,0 402x50
Restricted member row (component set property Kind) 370x60 AL=H gap=12 pad=10/16/10/16
  Row 1 [Kind=Silenced] @16,124
  Row 2 [Kind=Silenced forever] @16,188   (rows stack at 64pt pitch)
  Anatomy: Alert/Avatar 40x40 r=20 fill=#e8996b @x+16; text column AL=V gap=2 @x+68 (name App/TextMedium fill={textMain}; status App/Default13Medium fill={textSecondary}); trailing pill AL=H pad=8/14/8/14 fill=#ffffff@0.12 r=16 95x33 with "Unsilence" App/TextSmall fill={textMain}, right edge at x+354
  Row 1 text: "Grampa" / "Silenced · until 6:02 PM"
  Row 2 text: "Web3theo" / "Silenced"   (untimed = forever)
```
