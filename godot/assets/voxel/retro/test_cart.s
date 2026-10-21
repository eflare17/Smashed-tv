| The games room's own Mega Drive test cartridge (Stage 7), so the TV has something to play before anyone adds their
| own games: a big checkerboard drifting across the screen; the d-pad scrolls it, B or C flashes it red and beeps.
| Build: m68k-linux-gnu-as -m68000 -o t.o test_cart.s && m68k-linux-gnu-ld -Ttext=0 --oformat binary -o test_cart.md t.o
| Owned by the voxel session.
	.text
	.org 0
	.long 0x00FFFE00
	.long start
	.rept 62
	.long rte_handler
	.endr
	.org 0x100
	.ascii "SEGA MEGA DRIVE "
	.ascii "(C)VOXL 2026.OCT"
	.org 0x120
	.ascii "SMASHED TEST CART"
	.org 0x150
	.ascii "SMASHED TEST CART"
	.org 0x180
	.ascii "GM 00000000-00"
	.org 0x190
	.ascii "J               "
	.org 0x1A0
	.long 0
	.long rom_end-1
	.long 0x00FF0000
	.long 0x00FFFFFF
	.org 0x1F0
	.ascii "JUE"
	.org 0x200
start:
	move.w #0x2700,%sr
	move.b 0xA10001,%d0
	andi.b #0x0F,%d0
	beq.s 1f
	move.l #0x53454741,0xA14000
1:
	lea 0xC00004,%a0
	lea 0xC00000,%a1
	lea vdpregs(%pc),%a2
	moveq #10,%d7
2:
	move.w (%a2)+,(%a0)
	dbra %d7,2b
	| the palette: background, yellow, blue, magenta
	move.l #0xC0000000,(%a0)
	move.w #0x0400,(%a1)
	move.w #0x00EE,(%a1)
	move.w #0x0E40,(%a1)
	move.w #0x0E0E,(%a1)
	| tile 1 all colour 1, tile 2 all colour 2
	move.l #0x40200000,(%a0)
	move.l #0x11111111,%d0
	moveq #7,%d7
3:
	move.l %d0,(%a1)
	dbra %d7,3b
	move.l #0x22222222,%d0
	moveq #7,%d7
4:
	move.l %d0,(%a1)
	dbra %d7,4b
	| plane A (0xC000, 64 x 32): a checkerboard of 4 x 4 tile squares
	move.l #0x40000003,(%a0)
	moveq #0,%d6
5:
	moveq #0,%d5
6:
	move.w %d6,%d0
	lsr.w #2,%d0
	move.w %d5,%d1
	lsr.w #2,%d1
	eor.w %d1,%d0
	andi.w #1,%d0
	addq.w #1,%d0
	move.w %d0,(%a1)
	addq.w #1,%d5
	cmpi.w #64,%d5
	bne.s 6b
	addq.w #1,%d6
	cmpi.w #32,%d6
	bne.s 5b
	| the pad: TH an output, high
	move.b #0x40,0xA10009
	move.b #0x40,0xA10003
	moveq #0,%d3
	moveq #0,%d4
	moveq #0,%d5
loop:
7:
	move.w (%a0),%d0
	btst #3,%d0
	bne.s 7b
8:
	move.w (%a0),%d0
	btst #3,%d0
	beq.s 8b
	addq.w #1,%d3
	move.b 0xA10003,%d1
	not.b %d1
	btst #2,%d1
	beq.s 9f
	addq.w #2,%d4
9:
	btst #3,%d1
	beq.s 10f
	subq.w #2,%d4
10:
	btst #0,%d1
	beq.s 11f
	subq.w #2,%d5
11:
	btst #1,%d1
	beq.s 12f
	addq.w #2,%d5
12:
	| scroll: drifting left, and where the d-pad has moved it
	move.l #0x7C000003,(%a0)
	move.w %d4,%d0
	sub.w %d3,%d0
	move.w %d0,(%a1)
	move.l #0x40000010,(%a0)
	move.w %d5,(%a1)
	| colour 1 cycles; B or C: red
	move.l #0xC0020000,(%a0)
	move.w %d3,%d0
	lsr.w #3,%d0
	andi.w #0x0EEE,%d0
	andi.b #0x30,%d1
	beq.s 13f
	move.w #0x000E,%d0
13:
	move.w %d0,(%a1)
	| a beep while B or C is held
	tst.b %d1
	beq.s 14f
	move.b #0x8E,0xC00011
	move.b #0x0F,0xC00011
	move.b #0x90,0xC00011
	bra loop
14:
	move.b #0x9F,0xC00011
	bra loop
rte_handler:
	rte
vdpregs:
	.word 0x8004, 0x8144, 0x8230, 0x8407, 0x8578, 0x8B00, 0x8C81, 0x8D3F, 0x8F02
	.word 0x9001, 0x8700
	.org 0x2000
rom_end:
