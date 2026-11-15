# Shelf

An interface plugin for EmuDEN's Home screen. Pick it under Settings, Interface.

Every game is a 3D object on a lit shelf, in the shape of what that console's games came in:
cartridges, cards, cases and jewel cases. The selected one stands forward and turns gently,
and a case with a disc slides it out, spinning. The side objects turn towards it, with a
faint reflection on the floor. Starting a game lifts its cartridge, card or disc off the
shelf and drops it into a slot that closes, before EmuDEN's start-up screen. Consoles are
tabs along the top (L and R step through them), after a Continue tab with
the games last played on any of your devices and the moment each one was left.

It holds no code: EmuDEN's "shelf3d" layout draws it from `plugin.json`, with simple shapes
of its own (no models or artwork from anywhere else). See `docs/interface-plugins.md`.
