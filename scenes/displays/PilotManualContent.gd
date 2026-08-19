extends RefCounted
## The pilot's manual, as data: every chapter the manual shows, in the order the
## contents list shows them. PilotManual.gd renders these; it holds no prose of
## its own, so adding a chapter is an entry here and nothing else — the same
## catalog-not-branches shape as GameState.SCENARIOS and MfdUnit.PAGES.
##
## Each entry:
##   "id"    — stable key (the smoke test asserts the four checklists by id)
##   "group" — contents-list heading; a new value starts a new group
##   "title" — button label and chapter heading
##   "body"  — BBCode, with the placeholders below
##
## TONE: this is a ship's operating handbook, not a guide to a game. Write it the
## way a flight manual or an owner's manual is written — flat, declarative,
## addressed to the operator, and specific. State limits and procedures; do not
## sell them, rank them, or comment on how they feel to fly. Nothing may refer to
## the simulation, to scoring, or to the player as a player. Where a system is
## fitted but has no effect, say what it does and does not do in operational
## terms rather than describing what is or isn't implemented.
##
## SCOPE — what belongs in THIS document, which is the builder's:
##  * the ship, its systems, its limitations, and how to operate them;
##  * how a derelict hull behaves when it is cut, because that is what the torch
##    is for — a tool's manual describes what the tool does to the work.
## What does NOT belong here, and lives in TerminalProceduresContent instead:
##  * anything a harbour, a claim office or a buyer dictates — lane geometry,
##    speed limits, clearance, charges, prices, standing;
##  * how anyone else in the system behaves around a hull being salvaged.
## The test is authorship, not subject: the builder can state what the legs will
## take on touchdown, and cannot state where a harbour will let you put them.
##
## PLACEHOLDERS are substituted at render time from the LIVE bindings, so a
## checklist step names whatever the pilot actually has bound rather than a key
## this file guessed (see PilotManual._resolve and scenes/ui/BindingLabel.gd):
##   {{act:ops_cut}}                  one action
##   {{axis:pitch_down,pitch_up}}     a direction pair (one axis, or two keys)
##   {{throttle}}                     the throttle lever
##   {{sw:COWL}}                      a switch-panel legend
##   {{pwsw:CUTTER}}                  the switch panel legend driving a power channel
##
## EVERY NUMBER BELOW IS QUOTED FROM CODE. Nothing here is illustrative: the
## figures come from data/ships/kestrel.tres, the systems/*.gd constants and
## GameState, and CLAUDE.md carries a row requiring this file to move when they
## do. If you cannot point at the constant, do not write the number.

## The palette the bodies use, as literal hex (a const String can't be composed
## from another const in GDScript, so the bodies spell the codes out and these
## entries are the reference for which code means what).
const HDR := "#66ccff"      ## sub-heading blue
const DANGER := "#f2705c"   ## WARNING — damage to the ship, or salvage lost
const CAUTION := "#f2bf59"  ## CAUTION — an interlock, a refusal, a limit
const GOOD := "#59f28c"     ## a required condition, in a checklist
const FAINT := "#8c9eb8"    ## NOTE, and subordinate text

const CHAPTERS: Array[Dictionary] = [
	{
		"id": "front",
		"group": "SECTION 1 — GENERAL",
		"title": "Using this handbook",
		"body": """This handbook covers the SV Kestrel: what is fitted to her, what she will take, and how she is operated. It is issued by her builder and is correct for the ship wherever she is flown.

[color=#66ccff]HOW IT IS ARRANGED[/color]
[b]SECTION 1 — GENERAL[/b] ......... this page, and the ship's leading particulars
[b]SECTION 2 — SYSTEMS[/b] ......... each system, its limits, and its interlocks
[b]SECTION 3 — SALVAGE[/b] ......... how a derelict hull behaves under the torch
[b]SECTION 4 — PROCEDURES[/b] ...... the four normal procedures

[color=#66ccff]WHAT IS NOT IN THIS HANDBOOK[/color]
The builder can tell you what the ship will do. It cannot tell you what a harbour, a claim office or a buyer will require of you, and does not try: those are set by others, are changed by others without this handbook being reissued, and differ from berth to berth.

Carry the [b]TERMINAL PROCEDURES[/b] alongside this handbook for the berth you are working. It holds the approach lane and its plate, speed and clearance rules, charges, local notices and the schedule of prices.

[color=#f2bf59]CAUTION — Where a printed figure and an in-flight instrument disagree, the instrument is correct.[/color] This applies to anything published by someone other than the builder: the MFD [b]DOCK[/b] and [b]MARKET[/b] pages read live state, and a printed procedure records only what was in force when it was issued.

[color=#66ccff]CONTROLS[/color]
Controls are named throughout as they are [b]currently assigned[/b]. A control with no assignment is shown as [color=#f2bf59]NOT ASSIGNED[/color]; assign it at CONTROLS (F7) before relying on the procedure that names it.

[color=#8c9eb8]NOTE — Figures are given in the ship's own units: metres, metres per second, tonnes, cubic metres, and credits. Ranges expressed in [b]u[/b] are sensor units as displayed on the Tactical SCOPE.[/color]""",
	},
	{
		"id": "ship",
		"group": "SECTION 1 — GENERAL",
		"title": "Description",
		"body": """The [b]SV KESTREL[/b] is a single-seat salvage cutter. It carries a cutting torch on the starboard wing, a cargo hatch in the nose, four landing legs, and a reactor of limited output which is divided between four systems by the pilot.

[color=#66ccff]PERFORMANCE[/color]
Main thruster acceleration, full THRUST allocation ....... [b]4.0 m/s²[/b]
Attitude rate, full control deflection, all axes ......... [b]45°/s[/b]
Maximum speed ........................................... [b]25 m/s[/b]
Secondary thrusters, rated as a fraction of main ........ [b]50%[/b]
Approach autopilot closing speed, maximum ............... [b]8 m/s[/b]

Acceleration falls in proportion to the THRUST allocation. The secondary thrusters — lateral, vertical and reverse — are supplied by the same drive and are governed by the same allocation.

[color=#66ccff]CARGO[/color]
Hold capacity ........................................... [b]40.0 t / 30.0 m³[/b]

Both limits are checked when an item is stowed. Whichever is reached first governs.

[color=#66ccff]HULL[/color]
The hull is divided into six sections — BOW, PORT, STBD, CORE, AFT and DRIVE — each carrying its own integrity figure. Integrity is displayed on the hull diagram of the Tactical SCOPE.

This is not a new ship. Integrity at the start of a tour is BOW 0.96, PORT 0.88, STBD 0.92, CORE 1.00, AFT 0.90, DRIVE 0.85.

[color=#f2705c]WARNING — No repair facility is available on this circuit.[/color] Hull damage is permanent for the duration of the tour. No section will fall below 0.05 and no accumulation of damage will disable the ship, but nothing will restore what has been lost. The hull diagram is a running record of the tour.

[color=#f2705c]WARNING — DRIVE integrity governs the stability augmentation.[/color] The reaction control runs are carried in the DRIVE section. Authority is unimpaired at 0.80 and above, falls in proportion below it, and is lost entirely at 0.30. Heavy landings, flight over the gear limit with the legs out, and structural collapse all wear this section. See [b]Flight controls[/b].

[color=#8c9eb8]NOTE — The Kestrel carries no propellant. Thrust is limited by electrical allocation alone, and there is no refuelling requirement.[/color]""",
	},
	{
		"id": "flight",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Flight controls",
		"body": """[color=#66ccff]ATTITUDE[/color]
The ship carries rotational momentum. The attitude controls do not turn the hull directly: they command a rate, and the stability augmentation holds the hull to it.

Full deflection commands 45°/s. Returning the controls to centre commands zero, and the augmentation removes the remaining rate — in about a fifth of a second at full authority. Rotation imparted by a collision is removed the same way.

Pitch .......... {{axis:pitch_down,pitch_up}}
Yaw ............ {{axis:yaw_left,yaw_right}}
Roll ........... {{axis:roll_left,roll_right}}

[color=#66ccff]STABILITY AUGMENTATION[/color]
The augmentation is fitted to both axes of motion. On the attitude axes it holds the commanded rate and removes residual rotation. On the translation axes it bleeds off any axis the pilot is [b]not[/b] commanding, at one of two rates:

[b]STATION-KEEPING[/b] — every translation control released, including the throttle. Approximately 30% of remaining velocity per second, on all three axes. The ship coasts to a stop.
[b]FLYING[/b] — any translation control under command. Approximately 10% per second, on the uncommanded axes only. A sidestep is not wiped out the moment the control is released, but it will not be held indefinitely either.

[color=#8c9eb8]NOTE — Displacing the ship sideways and holding the offset is flown, not trimmed. Under way the augmentation will slowly return the ship to its heading; re-apply lateral thrust to hold a standoff off the lane.[/color]

It is engaged at power-up. {{act:fbw_mode_cycle}} switches it off and on. The Main display annunciates [b]ASSIST OFF[/b] or [b]ASSIST DEGRADED[/b] whenever it is not delivering full authority; nothing is annunciated when it is.

Authority is the product of two figures. THRUST allocation carries it unimpaired at 0.40 and above and in proportion below. DRIVE integrity carries it unimpaired at 0.80 and above, in proportion below, and not at all at 0.30. See [b]Description — HULL[/b].

[color=#f2bf59]CAUTION — The augmentation shares the THRUST channel with the manoeuvring thrusters.[/color] Allocation drawn down to feed the torch is taken out of stability authority at the same time.

[color=#f2705c]WARNING — With the augmentation off or unpowered, the controls command torque and nothing else.[/color] Every rate started must be stopped by the pilot on the opposite control. The ship remains flyable in this condition and will not right itself.

[color=#66ccff]TRANSLATION[/color]
Translation is not rate-commanded. Thrust accelerates the ship and the resulting velocity persists.

Lateral ........ {{axis:strafe_left,strafe_right}}
Vertical ....... {{axis:thrust_down,thrust_up}}
Fore and aft ... {{axis:thrust_back,thrust_forward}}
Throttle ....... {{throttle}}

[color=#66ccff]THROTTLE[/color]
The throttle has two command laws, selected with {{act:throttle_cmd_toggle}}.

[b]SPEED[/b] (normal). The lever commands a proportion of maximum speed. Set to 50%, the ship accelerates to 12.5 m/s and holds it.
[b]THRUST[/b] (alternate). The lever commands acceleration directly. No speed is held.

Reverse is limited to 50% of the lever's forward authority under either law.

[color=#66ccff]APPROACH AUTOPILOT[/color]
The approach autopilot is the only autopilot fitted; the stability augmentation above is not one, and holds no course. The autopilot closes on the selected structural member and holds station on it while the derelict rotates, then indicates MATCHED.

[color=#f2bf59]CAUTION — The autopilot translates only. It will not turn the ship,[/color] and it cannot match the derelict's rotation. Pointing the ship at the member remains a pilot task throughout.

To engage, the throttle must be below 40% travel. Above that the engagement is refused:
[i]"APPROACH INHIBITED — THROTTLE PAST 40%, EASE BACK TO ARM"[/i]

The autopilot disengages and returns control to the pilot on any lateral, vertical or attitude demand beyond 0.2 deflection, on throttle movement beyond the 40% band, or on collision:
[i]"AUTOPILOT DISENGAGED — MANUAL CONTROL"[/i]

[color=#8c9eb8]NOTE — No en-route autopilot is fitted. Transits between the claim and the station's outer approach are flown by the ship's own navigation; everything within the approach is hand-flown.[/color]""",
	},
	{
		"id": "power",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Electrical & power",
		"body": """Reactor output is divided between four channels. Each is allocated between [b]0.00[/b] and [b]1.00[/b] and is set on an MFD [b]POWER[/b] page.

[color=#66ccff]CHANNELS[/color]
[b]THRUST[/b] — supplies the main and secondary thrusters and the approach autopilot. At zero allocation the ship will not manoeuvre.
[b]CUTTER[/b] — supplies the cutting torch. Minimum for operation [b]0.20[/b]. A fall below 0.20 during a cut terminates it.
[b]SENSORS[/b] — supplies the structural scan. Minimum for operation [b]0.10[/b].
[b]LIFE[/b] — supplies the habitat. It has no bearing on the performance of any other system. Carry it at full.

[color=#f2bf59]CAUTION — The CUTTER channel is at zero on power-up.[/color] Allocation at power-up is THRUST 0.80, CUTTER 0.00, SENSORS 0.60, LIFE 1.00. The torch will not fire until the channel is raised, and raising it is a required step on every tour.

[color=#66ccff]REACTOR LOADING[/color]
Total draw is displayed against a reference figure of [b]2.5[/b] on the POWER page header, which changes colour when the figure is exceeded. No interlock prevents the pilot from exceeding it and no system is shed automatically. The indication is the only warning given.

[color=#66ccff]SETTING A CHANNEL[/color]
Any of the following may be used. All three act on the same allocation.
· The sliders on an MFD POWER page.
· The panel switches — THRUST {{pwsw:THRUST}}, SENSORS {{pwsw:SENSORS}}, CUTTER {{pwsw:CUTTER}}, LIFE {{pwsw:LIFE}}. The first three select high [b]0.80[/b] or low [b]0.20[/b]. LIFE selects [b]1.00[/b] or low.
· An assigned analogue axis, which acts as a slider; or an assigned key or button, which steps the allocation by 0.10.

[color=#66ccff]MASTER SWITCHES[/color]
[b]{{sw:MASTER_ALT}} — OFF.[/b] Emergency configuration. THRUST and LIFE to 1.00, CUTTER and SENSORS to zero, overriding the selected allocation.
[b]{{sw:MASTER_BAT}} — OFF.[/b] All channels to zero. This condition overrides the alternator switch.

[color=#f2bf59]CAUTION — With either master switch off the allocation is locked[/color] and cannot be altered from any station. Panel switch positions continue to be registered and take effect when power is restored; slider movements made during the lockout are not retained. If the allocation will not respond, check both master switches first.

[color=#66ccff]EMISSIONS[/color]
Each master switch turned off halves the ship's signature to passive detection — one switch off gives one half, both give one quarter. A patrol must close to the corresponding fraction of its normal 60 m enforcement range before it can act.""",
	},
	{
		"id": "sensors",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Sensors",
		"body": """Three sensor modes are available, selected with {{act:sensor_mode_cycle}} or from the mode bar on an MFD [b]SALVAGE[/b] page.

Mode ........ Range ........ Sweep
[b]PASSIVE[/b] ..... 600 u ......... 0.2 rev/s
[b]ACTIVE[/b] ...... 250 u ......... 0.5 rev/s
[b]STRUCT[/b] ...... 250 u ......... 0.35 rev/s

In STRUCT the Tactical SCOPE presents the derelict's structural diagram in place of the contact plot.

[color=#8c9eb8]NOTE — PASSIVE and ACTIVE differ in display range and sweep rate only. Neither conceals contacts from the ship, nor the ship from others. Signature is governed by the master switches — see Electrical & power.[/color]

[color=#66ccff]STRUCTURAL SCAN[/color]
The scan requires all of the following conditions together:
· Sensor mode ................ [b]STRUCT[/b]
· Range to the derelict ...... [b]300 u or less[/b]
· SENSORS allocation ......... [b]0.10 or greater[/b]

The scan runs at a rate proportional to the SENSORS allocation against a five-second reference: approximately [b]5 seconds[/b] at full allocation and [b]50 seconds[/b] at the minimum. Completion is annunciated:
[i]"STRUCTURAL SCAN COMPLETE — N MEMBERS RESOLVED, M CARRYING FRAME STRESS"[/i]

Until the scan is complete no cutting target can be selected, and the SALVAGE page reads:
[i]"NO STRUCTURAL DATA — SCAN THE WRECK (STRUCT MODE)"[/i]

[color=#66ccff]SCAN PRODUCT[/color]
The scan resolves the derelict into seven structural members and reports, for each, its material, its approximate yield, and its [b]load[/b] — the proportion of frame stress it carries. Load governs both the disturbance caused by severing the member and the difficulty of holding the cut. The diagram is presented on the Tactical SCOPE; the same members are listed for selection on an MFD SALVAGE page.""",
	},
	{
		"id": "cutter",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Cutting torch",
		"body": """The torch is mounted on the starboard wing and is fired at a seam on the selected member. Trigger: {{act:ops_cut}}.

The trigger has two functions. From a matched target it [b]opens the alignment[/b]; it does not cut. Pressed a second time during alignment it commits the cut at the quality then held.

[color=#66ccff]CONDITIONS FOR FIRING[/color]
The following are tested in order. The first failure is annunciated and the trigger has no further effect.
1. On station at the claim.
2. [b]Cargo hatch secured[/b] — [i]"CUT ABORT — SECURE CARGO HATCH FIRST"[/i]
3. [b]Landing gear stowed[/b] — [i]"CUT ABORT — STOW THE LANDING GEAR FIRST"[/i]
4. [b]A serviceable member selected[/b] — [i]"CUT ABORT — NO VALID MEMBER SELECTED"[/i]
5. [b]Approach state MATCHED[/b] — [i]"CUT ABORT — NOT IN CUTTING RANGE (MATCH VELOCITY FIRST)"[/i]
6. [b]CUTTER allocation 0.20 or greater[/b] — [i]"CUT ABORT — CUTTER UNPOWERED (RAISE CUTTER ALLOCATION)"[/i]

[color=#f2bf59]CAUTION — Alignment requires at least half stability authority.[/color] Aiming the cutting head takes the pitch and yaw controls away from flying the ship, so residual rotation cannot be corrected while it is in progress. Below half authority the alignment is refused, and authority lost during one ends it:
[i]"CUT ABORT — STABILISATION DEGRADED (CHECK FLIGHT ASSIST AND THRUST ALLOCATION)"[/i]
[i]"ALIGNMENT LOST — STABILISATION DEGRADED"[/i]

[color=#8c9eb8]NOTE — No separate cutting range is judged by the pilot. The MATCHED indication is the range condition: the autopilot establishes the standoff the torch requires. The torch cannot be fired under manual control at any distance.[/color]

[color=#66ccff]ALIGNMENT[/color]
The seam is a fixed point on the member. It traverses the field of view because the derelict is rotating; the autopilot matches the derelict's translation but not its rotation, and tracking the seam is therefore a continuous manual task.

The torch is steered on the [b]pitch and yaw[/b] controls, which are transferred to the torch for the duration of the alignment and do not disengage the autopilot while so transferred.

Hold the reticle within the tolerance ring to build [b]LOCK[/b]. Allowing it outside the outer radius builds [b]SLIP[/b] instead.

Lock builds at 0.7 per second on the seam and decays at 0.9 per second off it. Slip builds at 0.6 per second and recovers at 0.4 per second.

[color=#f2bf59]CAUTION — Lock decays faster than it builds.[/color] Slip reaching full terminates the alignment and imposes a 0.05 increase in structural risk:
[i]"ALIGNMENT LOST — TORCH SLIPPED"[/i]

Full lock commits the cut automatically. Committing before full lock trades cut quality for time.

[color=#66ccff]EFFECT OF ALIGNMENT QUALITY[/color]
Quality is taken from the best sustained lock, weighted by proximity to the centre of the ring. It governs three things:
[b]Rate[/b] ..... 45% of rated at zero quality, rising to 100% at full.
[b]Disturbance[/b] ... structural risk increase multiplied by 1.6 at zero quality, 0.6 at full.
[b]Yield[/b] .... 55% of the member's salvage recovered at zero quality, 100% at full.

Rated cut rate is 0.35 of a member per second at full allocation and full quality. Representative times: [b]3 seconds[/b] at full allocation and full quality; [b]6 seconds[/b] at full allocation and zero quality; [b]in excess of 30 seconds[/b] at minimum allocation and zero quality.

[color=#66ccff]INTERLOCKS DURING OPERATION[/color]
An alignment or a cut in progress is terminated by loss of the MATCHED condition, by CUTTER allocation falling below 0.20, by opening the cargo hatch, by selection of another member, by collision, or by collapse of the frame.

[color=#8c9eb8]NOTE — The torch has no thermal limit and no duty cycle. Operation is continuous.[/color]""",
	},
	{
		"id": "scoop",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Cargo hatch & recovery",
		"body": """A severed member is not taken aboard automatically. It separates as a free body carrying the derelict's rotation together with a separation impulse from the torch, and must be recovered.

No grapple, magnet or manipulator is fitted. The hatch is an aperture in the nose and recovery is performed by flying the aperture onto the piece.

Hatch control: {{act:cargo_hatch_open}}, the {{sw:COWL}} switch, or the hatch control on the MFD [b]SCOOP[/b] page, which the primary MFD presents automatically when the hatch is opened.

[color=#66ccff]CONDITIONS FOR RECOVERY[/color]
All four must be held together.
Hatch ................................. [b]OPEN[/b]
Range, surface to surface ............. [b]less than 4.0 m[/b]
Relative velocity ..................... [b]less than 1.5 m/s[/b]
Bearing off the nose .................. [b]35° or less[/b]

Held together for [b]1.5 seconds[/b], the piece is stowed. On the loss of any condition the recovery indication decays at 1.5 times the rate at which it built.

The HUD marker and the SCOOP page both annunciate the governing condition, in order of priority: [i]CLOSE IN[/i], [i]OFF-AXIS[/i], [i]MATCH SPEED[/i], [i]SCOOPING[/i].

[color=#66ccff]HATCH INTERLOCKS[/color]
The hatch is required open for recovery. While open it [b]inhibits the cutting torch[/b], [b]inhibits docking[/b] and [b]inhibits departure[/b]. Opening it terminates any alignment or cut in progress.

[color=#f2bf59]CAUTION — Secure the hatch on completion of recovery.[/color] A pulsing CARGO HATCH OPEN indication is displayed on the HUD throughout, and no further cutting or docking is possible until the hatch is closed.

[color=#66ccff]HOLD FULL[/color]
Where a piece exceeds the remaining capacity the recovery is refused and the indication resets:
[i]"HOLD FULL — <NAME> ADRIFT (JETTISON TO MAKE ROOM)"[/i]

Capacity is released by jettisoning from an MFD [b]CARGO[/b] page.

[color=#f2705c]WARNING — Jettisoned cargo is destroyed. It cannot be recovered.[/color]

[color=#66ccff]TITLE TO SEVERED PIECES[/color]
A severed piece is unclaimed until recovered, and title passes to whichever ship recovers it. The rival cutter working the claim recovers pieces on the same terms, [b]including pieces severed by this ship[/b].

Recovery is not available away from the claim; the SCOOP page reads COLLECTION SUSPENDED.

[color=#f2705c]WARNING — Pieces left adrift when the claim is vacated are abandoned.[/color] The ship returns to a fresh derelict, not to previously severed pieces.""",
	},
	{
		"id": "gear",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Landing gear",
		"body": """Four legs. Selector: {{act:landing_gear}}, or the panel's {{sw:GEAR_DOWN}} / {{sw:GEAR_UP}} lever.

[color=#66ccff]OPERATION[/color]
Travel time, either direction ........... [b]3 seconds[/b]
Maximum speed, gear extended ............ [b]18 m/s[/b]

Selecting a position begins the travel; the gear is not in the selected position until the travel is complete. GEAR IN TRANSIT is displayed with the percentage travelled, followed by GEAR DOWN at the stops. Only [b]down and locked[/b] satisfies the landing condition and the station's final gate.

[color=#f2bf59]CAUTION — Select the gear down early.[/color] Three seconds of travel cannot be made up on short final, and arrival at the final gate with the gear not locked results in a go-around.

[color=#f2705c]WARNING — Exceeding 18 m/s with the gear extended wears the DRIVE section[/color] for as long as the condition persists. A pulsing GEAR OVERSPEED indication is displayed.

[color=#66ccff]INTERLOCK[/color]
An extended leg lies in the arc of the cutting torch. The gear therefore inhibits the torch in the same manner as the cargo hatch:
[i]"CUT ABORT — STOW THE LANDING GEAR FIRST"[/i]

[color=#66ccff]DEPARTURE[/color]
Outbound the requirement is reversed. The gear is to remain [b]down[/b] until the berth bay is cleared — raising it within the bay is a violation — and is to be [b]stowed[/b] before Control will release the ship for the transit.""",
	},
	{
		"id": "landing-limits",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Landing limitations",
		"body": """These are the limits the landing gear will accept. They are properties of the ship and apply at any berth, on any circuit, whatever the harbour publishes.

[color=#66ccff]LIMITS AT CONTACT[/color]
Assessed at the moment the legs reach deck height.
Gear ..................... [b]down and locked[/b]
Attitude ................. [b]within 20° of level[/b]
Lateral drift ............ [b]below 2.0 m/s[/b]
Sink rate ................ [b]below 5.0 m/s[/b]

Contact outside any one of these is rejected: the ship is thrown clear and returns to the pattern.

[color=#66ccff]SINK RATE[/color]
Below [b]1.5 m/s[/b] .......... no wear
Below [b]3.0 m/s[/b] .......... no wear
Above [b]3.0 m/s[/b] .......... DRIVE section wear, in proportion to the excess
Above [b]5.0 m/s[/b] .......... rejected; the legs will not accept it

[color=#f2bf59]CAUTION — The ship lands on its legs, level.[/color] Lowering the nose toward the pad both exceeds the attitude limit and brings the bow into contact with the deck. The pad lies directly beneath the ship on short final; use the BELLY camera view.

[color=#f2705c]WARNING — Damage taken on a heavy arrival cannot be repaired.[/color] See Description.

[color=#8c9eb8]NOTE — Where the ship may be set down, how the arrival is assessed, and what it earns are the harbour's business, not the builder's. See the [b]TERMINAL PROCEDURES[/b] for the berth.[/color]""",
	},
	{
		"id": "collision",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Hull & collision",
		"body": """All structure is solid: the derelict's unsevered members, debris, the station, the rival cutter, the patrol and station traffic. A severed member ceases to obstruct, and the gap it leaves may be flown through.

[color=#66ccff]IMPACT[/color]
Closing speed below ........ [b]1.5 m/s[/b] — the ships separate; no damage.
Damage above that figure ... [b]0.03 integrity per m/s[/b] of excess.
Maximum, single impact ..... [b]0.6 integrity[/b]
Rebound .................... [b]30% of closing speed[/b]

The section damaged is determined by the direction of the impact.

[color=#8c9eb8]NOTE — An impact from astern is recorded against DRIVE. The AFT section is damaged only by collapse and by debris.[/color]

An impact during an autopilot approach returns control to the pilot.

[color=#66ccff]COLLAPSE DAMAGE[/color]
Collapse of the derelict's frame within 25 m damages two sections at random, each by between 0.10 and 0.25 integrity.

[color=#66ccff]INDICATION[/color]
The hull diagram on the Tactical [b]SCOPE[/b] presents all six sections by condition. Selecting a section reports its integrity figure.

[color=#f2705c]WARNING — No repair is available.[/color] Sections do not recover, and integrity lost is lost for the remainder of the tour.""",
	},
	{
		"id": "nav",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Scope & contacts",
		"body": """[color=#66ccff]SCOPE[/color]
The Tactical [b]SCOPE[/b] presents a ship-relative plot: own ship at the centre, nose uppermost, with range rings and bearing marks at 30° intervals. Range and sweep rate follow the sensor mode. Hostile contacts are shown as pulsing triangles, others as squares, and the designated contact carries a ring.

In [b]STRUCT[/b] the plot is replaced by the derelict's structural diagram, members scaled by load, with their connections shown, severed and lost members struck through, and the selected member's load, projected risk and expected yield reported beneath.

[color=#66ccff]CONTACTS[/color]
The designated contact is stepped with {{act:contact_cycle}}, or selected from the list on an MFD [b]CONTACTS[/b] page. A designated contact is shown on the HUD with corner brackets, identification and range. A hostile contact within 25 m adds a pulsing frame and a [b]PROXIMITY[/b] warning.

Contacts include the derelict, unstable debris, the rival cutter, the claim operator's patrol, severed pieces adrift, and, at the station, vessels in the pattern.

[color=#66ccff]CHART[/color]
The Tactical [b]CHART[/b] mode presents a system schematic. Its content is not builder data and is not reproduced here — see the [b]TERMINAL PROCEDURES[/b].

[color=#8c9eb8]NOTE — No waypoint, route or navigation-computer facility is fitted to this ship.[/color]""",
	},
	{
		"id": "displays",
		"group": "SECTION 2 — SYSTEMS",
		"title": "Instruments & displays",
		"body": """[color=#66ccff]THE FOUR DISPLAYS[/color]
[b]MAIN[/b] — the hull camera with the flight HUD superimposed. The camera may be trained away from the nose without turning the ship.
[b]TACTICAL[/b] — presentation only. SCOPE (contact plot or structural diagram, hull condition, structural risk) and CHART, selected with {{act:tactical_view_cycle}}.
[b]MFD[/b] — two independent units. Pages: CHECKLIST, POWER, CARGO, SALVAGE, ALIGN, SCOOP, MARKET, DOCK, CONTACTS. The page index is reached with {{act:mfd_a_menu}} and {{act:mfd_b_menu}}. The primary unit presents ALIGN during an alignment, SCOOP while the hatch is open, and DOCK during an approach, returning to the previous page on completion.

[color=#66ccff]CHECKLIST PAGE[/color]
The procedures of SECTION 4 are carried on the CHECKLIST page, one line to each item, marked against the condition of the ship. Select a procedure from the page index; return to it with BACK.

An item the ship is able to test carries its live value beside its limit and is marked [color=#59f28c]OK[/color] when satisfied. An item that does not yet apply — a touchdown limit before the ship is over a pad, the gear stow before the bay is cleared — is marked with a dash and is not counted against the procedure.

A small number of items cannot be tested from aboard: attitude held by hand during an approach, and stowage, which is annunciated and then over. These carry a box and are marked off by the operator. No other item can be marked by hand.

[color=#8c9eb8]NOTE — The page reads the same conditions the interlocks themselves test. An item shown unsatisfied is the item that will refuse the command.[/color]

[color=#8c9eb8]NOTE — Marks made by hand are cleared when the ship begins a new run.[/color]
[b]CAMERA[/b] — a second external view of own ship: REAR, SIDE, CHASE, TOP, BELLY. Stepped with {{act:view_cycle}}, or selected directly — {{act:view_rear}}, {{act:view_side}}, {{act:view_chase}}, {{act:view_top}}, {{act:view_belly}}.

[color=#f2bf59]CAUTION — BELLY is the landing view.[/color] The pad lies directly beneath the ship on short final and the hull camera is trained forward. Without the belly view the touchdown point cannot be seen.

[color=#66ccff]FLIGHT HUD[/color]
[b]Nose reticle[/b] — marks the direction in which the hull is pointed. It moves off centre as the camera is trained away, reaching the edge of the display at full deflection.
[b]Drift brackets[/b] — displaced from the nose reticle in proportion to lateral velocity. Coincident with the reticle, lateral drift is nulled. Speed along the nose is shown at VEL and is not represented here.
[b]VEL / HDG / EL[/b] — lower left. Speed, and the bearing and elevation of the camera, not of the hull. VEL is shown in red above an ATC speed limit.
[b]Cut target[/b] — a diamond on the selected member with identification and range, replaced by an edge marker when off-screen. Amber while closing; green with MATCHED — FIRE TO ALIGN when the approach has matched on that member.
[b]Alignment reticle[/b] — displayed over the member during alignment: seam, torch reticle, tolerance ring, lock arc and SLIP warning.
[b]Salvage markers[/b] — a diamond on each adrift piece with identification and range. With the hatch open, relative speed and a recovery ring are added, together with the governing condition.
[b]CARGO HATCH OPEN[/b] — upper right, pulsing, whenever the hatch is open.
[b]Gear[/b] — GEAR IN TRANSIT with percentage, then GEAR DOWN; GEAR OVERSPEED in red above 18 m/s.
[b]ATC[/b] — the standing instruction during an approach, with altitude and sink rate on final.

[color=#8c9eb8]NOTE — Reactor loading and hull condition are not repeated on the flight HUD. They are presented on the MFD POWER page and the Tactical SCOPE respectively.[/color]""",
	},
	{
		"id": "risk",
		"group": "SECTION 3 — SALVAGE OPERATIONS",
		"title": "Structural loading",
		"body": """[color=#8c9eb8]The torch is a tool for taking a loaded structure apart, and this section describes how such a structure behaves while you do it. It is given because the ship carries the instrument that measures it, and because the ship is inside the radius when a frame lets go.[/color]

The derelict is a loaded frame, and each cut redistributes the load carried by the remainder. The condition of the frame is displayed as [b]STRUCTURAL RISK[/b] on the Tactical SCOPE.

[color=#66ccff]BEHAVIOUR[/color]
Severing a member produces an immediate increase in risk and also raises the resting value toward which the reading settles. [b]The resting value does not fall.[/b]

Both effects scale sharply with the load carried by the member. A primary member such as the spine truss produces a large increase; a secondary panel produces very little. The projected increase for each member is listed against it on the MFD SALVAGE page before selection.

Alignment quality multiplies the increase between 0.6 and 1.6 — see Cutting torch.

[color=#66ccff]COLLAPSE[/color]
Below a risk of [b]0.55[/b] the frame will not collapse. Above that figure collapse becomes a probability per second, rising with the margin above 0.55.

[color=#f2705c]WARNING — Collapse destroys every member not yet severed.[/color] All salvage remaining attached to the frame is lost at the same instant.

[color=#f2705c]WARNING — Collapse within 25 m damages the ship.[/color] Two hull sections each lose between 0.10 and 0.25 integrity.

[color=#66ccff]OPERATING PRACTICE[/color]
Secondary members may be taken at little cost to the frame. Primary members should be taken in the knowledge of the increase they produce and of the salvage still attached. Once the resting value is well above the collapse threshold, each further cut is taken against the value of the members remaining.""",
	},
	{
		"id": "checklist-departure",
		"group": "SECTION 4 — PROCEDURES",
		"title": "Departure",
		"body": """[color=#8c9eb8]Vacating a berth, and the systems set-up required from cold.

Items 1 to 5 are ship configuration. Items 6 onward are flown in compliance with the berth's departure procedure, which is not builder data — see the [b]TERMINAL PROCEDURES[/b].[/color]

[color=#66ccff]BEFORE DEPARTURE[/color]
[b]1  MASTER SWITCHES[/b] — {{sw:MASTER_BAT}} and {{sw:MASTER_ALT}} [color=#59f28c]ON[/color]
     [color=#8c9eb8]The allocation is locked while either is off. Complete this item first.[/color]
[b]2  POWER CHANNELS[/b] — [color=#59f28c]SET[/color]
     [color=#8c9eb8]THRUST raised. SENSORS raised if a scan is to be run on arrival. CUTTER is not required for the transit.[/color]
[b]3  CARGO HATCH[/b] — [color=#59f28c]SECURED[/color] · {{act:cargo_hatch_open}} or {{sw:COWL}}
     [color=#f2bf59]CAUTION — Departure is refused with the hatch open: "DEPARTURE HELD — SECURE CARGO HATCH FIRST"[/color]
[b]4  HOLD[/b] — [color=#59f28c]DISPOSED OF[/color]
     [color=#8c9eb8]Cargo carried out of the station is carried back to it.[/color]
[b]5  LANDING GEAR[/b] — [color=#59f28c]DOWN[/color]
     [color=#8c9eb8]The ship is standing on it. It remains down until the bay is cleared.[/color]

[color=#66ccff]LEAVING THE BERTH[/color]
[b]6  UNDOCK[/b] — {{act:market_depart}}, or DEPART on the MFD MARKET page
     [color=#8c9eb8]This lifts the ship off the pad and into the berth's departure hold. It is not the transit; the lane is flown first.[/color]
[b]7  DOCK PAGE[/b] — [color=#59f28c]SELECTED[/color]
     [color=#8c9eb8]Presented automatically on the primary MFD. It carries the berth's live requirements — speed, lane and clearance — for the rest of the departure.[/color]
[b]8  BERTH DEPARTURE PROCEDURE[/b] — [color=#59f28c]COMPLY[/color]
     [color=#8c9eb8]Clearance, the outbound lane and its limits are the berth's, and are given in the [b]TERMINAL PROCEDURES[/b] for the station you are leaving.[/color]
[b]9  LANDING GEAR[/b] — [color=#59f28c]DOWN UNTIL THE BAY IS CLEARED, THEN STOWED[/color] · {{act:landing_gear}}
     [color=#f2705c]WARNING — Above 18 m/s with the gear extended the DRIVE section wears continuously. Stow it as soon as the berth permits.[/color]
     [color=#8c9eb8]Three seconds of travel each way. When the gear may be raised, and the consequence of raising it early, are the berth's business.[/color]

[color=#8c9eb8]FROM COLD — On the first launch of a tour there is no berth to leave. Items 1 and 2 are the whole of the set-up, the gear is already stowed, and the ship begins on station at the claim.[/color]""",
	},
	{
		"id": "checklist-arrival",
		"group": "SECTION 4 — PROCEDURES",
		"title": "Arrival",
		"body": """[color=#8c9eb8]Vacating the claim and setting down on a berth pad.

This is the [b]ship's[/b] half of an arrival — what the Kestrel must be configured to, and what her legs will take. The approach itself belongs to the berth: its markers, corridors, speed limits and clearance rules are published by the harbour and are not reproduced here. Fly this alongside the [b]TERMINAL PROCEDURES[/b] for the station, and read the MFD DOCK page in flight.[/color]

[color=#66ccff]BEFORE LEAVING THE CLAIM[/color]
[b]1  CUTTING TORCH[/b] — [color=#59f28c]IDLE[/color]
     [color=#f2bf59]CAUTION — Departure is refused during a cut: "DEPARTURE HELD — CUTTER ACTIVE"[/color]
[b]2  ADRIFT PIECES[/b] — [color=#59f28c]RECOVERED[/color]
     [color=#f2705c]WARNING — Pieces left adrift are abandoned. The ship returns to a fresh derelict.[/color]
[b]3  CARGO HATCH[/b] — [color=#59f28c]SECURED[/color] · {{act:cargo_hatch_open}} or {{sw:COWL}}
     [color=#f2bf59]CAUTION — "DEPARTURE HELD — SECURE CARGO HATCH FIRST"[/color]
[b]4  OPERATOR[/b] — [color=#59f28c]SELECTED[/color] · DOCK on that operator's MFD MARKET column, or {{act:market_dock}}
     [color=#8c9eb8]An assigned control docks with the first operator listed. To select another, use the on-screen control.[/color]

[color=#66ccff]INBOUND[/color]
[b]5  DOCK PAGE[/b] — [color=#59f28c]SELECTED[/color]
     [color=#8c9eb8]The transit reaches the berth's outer approach only. The remainder is flown, on the berth's procedure.[/color]
[b]6  BERTH ARRIVAL PROCEDURE[/b] — [color=#59f28c]COMPLY[/color]
     [color=#8c9eb8]The approach lane, its markers and corridors, the speed limits, clearance and traffic rules are the berth's, and are given in the [b]TERMINAL PROCEDURES[/b] for the station you are approaching. Read them before you leave the claim.[/color]

[color=#66ccff]BEFORE FINAL[/color]
[b]7  LANDING GEAR[/b] — [color=#59f28c]DOWN AND LOCKED[/color] · {{act:landing_gear}}
     [color=#f2bf59]CAUTION — Three seconds of travel each way. Select it down early: it cannot be made up on short final, and berths require it locked before the last marker.[/color]
[b]8  CARGO HATCH[/b] — [color=#59f28c]SECURED[/color] (confirm) · {{act:cargo_hatch_open}} or {{sw:COWL}}
[b]9  CAMERA[/b] — [color=#59f28c]BELLY[/color] · {{act:view_belly}}
     [color=#8c9eb8]The pad ends up directly beneath the ship and the hull camera looks forward. Fly the descent on the belly view, the pad presentation on the DOCK page, and the HUD altitude and sink rate.[/color]

[color=#66ccff]TOUCHDOWN[/color]
[b]10 LIMITS[/b] — [color=#59f28c]CHECK[/color]
     · Gear down and locked
     · Attitude within [b]20°[/b] of level
     · Lateral drift below [b]2.0 m/s[/b]
     · Sink rate below [b]5.0 m/s[/b]; below [b]1.5 m/s[/b] for no wear
     [color=#f2bf59]CAUTION — The ship lands on its legs, level. Do not lower the nose toward the pad.[/color]
     [color=#8c9eb8]These are the legs' limits — see [b]Landing limitations[/b]. Where on the deck the ship may be put down, and how the arrival is judged, are the berth's.[/color]
[b]11 HOLD[/b] — [color=#59f28c]DISPOSE OF[/color]

[color=#8c9eb8]ABANDONING THE APPROACH — {{act:market_depart}} leaves the pattern and returns the ship to the claim, with the derelict as it was left.[/color]""",
	},
	{
		"id": "checklist-cutting",
		"group": "SECTION 4 — PROCEDURES",
		"title": "Cutting",
		"body": """[color=#8c9eb8]From arrival on station to a member severed and adrift.[/color]

[color=#66ccff]SURVEY[/color]
[b]1  SENSORS ALLOCATION[/b] — [color=#59f28c]0.10 MINIMUM[/color] · {{pwsw:SENSORS}} switch, or the MFD POWER page
[b]2  SENSOR MODE[/b] — [color=#59f28c]STRUCT[/color] · {{act:sensor_mode_cycle}}
[b]3  RANGE[/b] — [color=#59f28c]WITHIN 300 u[/color] of the derelict
[b]4  STRUCTURAL SCAN[/b] — [color=#59f28c]COMPLETE[/color]
     [color=#8c9eb8]Approximately 5 seconds at full allocation, 50 seconds at the minimum. No target can be selected until the scan is complete: "NO STRUCTURAL DATA — SCAN THE WRECK (STRUCT MODE)".[/color]

[color=#66ccff]TARGET[/color]
[b]5  CUT TARGET[/b] — [color=#59f28c]SELECTED[/color] · {{act:salvage_prev}} / {{act:salvage_next}}, or from the MFD SALVAGE list
     [color=#f2bf59]CAUTION — Select the target before engaging the approach. The autopilot closes on whichever member is selected.[/color]
     [color=#8c9eb8]The projected increase in structural risk is listed against each member. Secondary panels are inexpensive; the spine truss is not.[/color]

[color=#66ccff]APPROACH[/color]
[b]6  THROTTLE[/b] — [color=#59f28c]BELOW 40%[/color] · {{throttle}}
     [color=#f2bf59]CAUTION — "APPROACH INHIBITED — THROTTLE PAST 40%, EASE BACK TO ARM"[/color]
[b]7  APPROACH[/b] — [color=#59f28c]ENGAGE[/color] · {{act:ops_approach}}
[b]8  ATTITUDE[/b] — [color=#59f28c]PILOT[/color]
     [color=#f2bf59]CAUTION — The autopilot translates only. It will not turn the ship and cannot match the derelict's rotation. Keep the target in view on pitch and yaw.[/color]
[b]9  APPROACH STATE[/b] — [color=#59f28c]MATCHED[/color]
     [color=#8c9eb8]Indicated by MATCHED — FIRE TO ALIGN on the target marker. Selecting another member cancels the match and the approach must be re-engaged.[/color]

[color=#66ccff]BEFORE FIRING[/color]
[b]10 CUTTER ALLOCATION[/b] — [color=#59f28c]0.20 MINIMUM[/color] · {{pwsw:CUTTER}} switch, or the MFD POWER page
     [color=#f2bf59]CAUTION — The CUTTER channel is at zero on power-up. This item is required on every tour.[/color]
[b]11 CARGO HATCH[/b] — [color=#59f28c]SECURED[/color] · {{act:cargo_hatch_open}} or {{sw:COWL}}
[b]12 LANDING GEAR[/b] — [color=#59f28c]STOWED[/color] · {{act:landing_gear}}
     [color=#8c9eb8]An extended leg lies in the arc of the torch. Confirm following any station departure.[/color]

[color=#66ccff]CUT[/color]
[b]13 TRIGGER[/b] — [color=#59f28c]FIRE TO OPEN ALIGNMENT[/color] · {{act:ops_cut}}
     [color=#8c9eb8]This opens the alignment. It does not cut.[/color]
[b]14 SEAM[/b] — [color=#59f28c]TRACK[/color] on pitch and yaw
     [color=#8c9eb8]The seam traverses because the derelict is rotating. Hold within the tolerance ring to build lock; lock decays faster than it builds.[/color]
[b]15 COMMIT[/b] — [color=#59f28c]AUTOMATIC AT FULL LOCK[/color], or {{act:ops_cut}} to commit early
     [color=#8c9eb8]Quality governs cut rate, the increase in structural risk, and the salvage recovered in the piece.[/color]
[b]16 STRUCTURAL RISK[/b] — [color=#59f28c]MONITOR[/color]
     [color=#f2705c]WARNING — Above 0.55 the frame may collapse, destroying every member not yet severed.[/color]
[b]17 SEVERED PIECE[/b] — [color=#59f28c]PROCEED TO RECOVERY[/color]
     [color=#8c9eb8]The piece is adrift and is not aboard. See the Collecting procedure.[/color]

[color=#66ccff]IF THE TRIGGER HAS NO EFFECT[/color]
Refer to the annunciation. The conditions tested are, in order: cargo hatch secured, landing gear stowed, a serviceable member selected, approach MATCHED, CUTTER allocation at 0.20 or above.""",
	},
	{
		"id": "checklist-collecting",
		"group": "SECTION 4 — PROCEDURES",
		"title": "Collecting",
		"body": """[color=#8c9eb8]From a severed piece adrift to cargo stowed in the hold.[/color]

[color=#66ccff]BEFORE OPENING[/color]
[b]1  CUTTING TORCH[/b] — [color=#59f28c]IDLE[/color]
     [color=#f2bf59]CAUTION — Opening the hatch terminates any alignment or cut in progress.[/color]
[b]2  HOLD[/b] — [color=#59f28c]CHECK[/color] · MFD CARGO page
     [color=#8c9eb8]Capacity 40.0 t and 30.0 m³. A piece exceeding the remaining capacity cannot be taken aboard.[/color]

[color=#66ccff]RECOVERY[/color]
[b]3  CARGO HATCH[/b] — [color=#59f28c]OPEN[/color] · {{act:cargo_hatch_open}} or {{sw:COWL}}
     [color=#8c9eb8]The primary MFD presents the SCOOP page. CARGO HATCH OPEN is displayed on the HUD throughout.[/color]
[b]4  PIECE[/b] — [color=#59f28c]IDENTIFY[/color]
     [color=#8c9eb8]Marked on the HUD with identification and range; an edge marker is shown when off-screen.[/color]
[b]5  RANGE[/b] — [color=#59f28c]WITHIN 4.0 m[/color], surface to surface
     [color=#8c9eb8]Annunciated CLOSE IN until established.[/color]
[b]6  RELATIVE VELOCITY[/b] — [color=#59f28c]BELOW 1.5 m/s[/color]
     [color=#8c9eb8]Annunciated MATCH SPEED. Thrust along the drift indication on the SCOOP page to null it.[/color]
[b]7  BEARING[/b] — [color=#59f28c]WITHIN 35°[/color] of the nose
     [color=#8c9eb8]Annunciated OFF-AXIS. Bring the marker into the tolerance ring on pitch and yaw.[/color]
[b]8  ALL FOUR CONDITIONS[/b] — [color=#59f28c]HOLD 1.5 SECONDS[/color]
     [color=#f2bf59]CAUTION — The indication decays at 1.5 times the rate at which it builds. Establish the conditions, then hold them.[/color]
[b]9  STOWAGE[/b] — [color=#59f28c]CONFIRM[/color]
     [color=#8c9eb8]The recovery ring closes and stowage is annunciated in the log.[/color]

[color=#66ccff]ON COMPLETION[/color]
[b]10 REMAINING PIECES[/b] — [color=#59f28c]REPEAT FROM ITEM 4[/color]
     [color=#f2705c]WARNING — The rival cutter requires 6 m and 2 seconds to recover a piece, including one severed by this ship. Recover before working a further target.[/color]
[b]11 CARGO HATCH[/b] — [color=#59f28c]SECURED[/color] · {{act:cargo_hatch_open}} or {{sw:COWL}}
     [color=#f2bf59]CAUTION — The open hatch inhibits the torch, docking and departure.[/color]

[color=#66ccff]IF THE RECOVERY DOES NOT COMPLETE[/color]
The governing condition is annunciated beneath the marker in order of priority — [b]CLOSE IN[/b], [b]OFF-AXIS[/b], [b]MATCH SPEED[/b], [b]SCOOPING[/b] — and the SCOOP page reports each condition against its limit.

[color=#66ccff]IF THE HOLD IS FULL[/color]
[i]"HOLD FULL — <NAME> ADRIFT (JETTISON TO MAKE ROOM)"[/i]

Capacity is released from an MFD CARGO page with {{act:cargo_jettison}} or the on-screen control. Where a choice exists, jettison the commodity occupying the most volume per unit of value; volatiles occupy the most.

[color=#f2705c]WARNING — Jettisoned cargo is destroyed and cannot be recovered.[/color]

[color=#66ccff]BEFORE VACATING THE CLAIM[/color]
[color=#f2705c]WARNING — Any piece still adrift is abandoned.[/color] The ship returns to a fresh derelict, not to pieces previously severed.""",
	},
]
