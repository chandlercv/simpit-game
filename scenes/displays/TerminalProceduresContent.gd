extends RefCounted
## The TERMINAL PROCEDURES — the second document the ship carries, rendered by
## ManualViewer exactly as the pilot's handbook is, and opened from the launch
## title card alongside it.
##
## WHY IT IS A SEPARATE DOCUMENT. Everything in here is dictated by somebody
## other than the ship's builder — a harbour authority, a claim office, a buyer —
## and so has no business in an owner's manual. It changes without the handbook
## changing, it differs from berth to berth, and it binds the pilot rather than
## describing the ship. Nothing here may state a property of the Kestrel; if a
## figure is true of the ship wherever she is flown, it belongs in
## PilotManualContent instead.
##
## The dividing line that matters, and the one this split was drawn to fix:
##   * how a derelict hull behaves under the torch is the BUILDER's to describe,
##     because that is what the tool does to the work — it is in the handbook;
##   * how everyone ELSE behaves around a hull being salvaged — the rival, the
##     patrol, the buyers — is not, and is in here.
##
## Each chapter opens with the office that issued it. That masthead is the
## attribution; do not add a disclaimer saying what the chapter is not.
##
## TONE and PLACEHOLDERS are exactly as PilotManualContent documents them, and
## the same rule governs the figures: every one is quoted from
## systems/DockingSystem.gd, systems/ThreatSystem.gd, systems/MarketSystem.gd or
## the data/*.tres files. If you cannot point at the constant, do not write it.

## Issuing offices, used as chapter mastheads. The harbour and the claim office
## are distinct: Freehold holds this claim, but a berth may be taken at any of
## the three operators.
const HARBOUR := "HARBOUR CONTROL · TERMINAL PROCEDURES"
const CLAIM_OFFICE := "CLAIM OFFICE · NOTICE TO SALVORS, CLAIM 7741-C"
const AGENT := "COMMERCIAL AGENT · SCHEDULE OF REFERENCE PRICES"

const CHAPTERS: Array[Dictionary] = [
	{
		"id": "authority",
		"group": "GENERAL",
		"title": "Authority & currency",
		"body": """[color=#8c9eb8]HARBOUR CONTROL · TERMINAL PROCEDURES[/color]

These procedures are issued by the harbour and bind every vessel operating in its volume. They are not part of the SV Kestrel's handbook, are not issued by her builder, and are amended by the harbour without that handbook being reissued.

[color=#f2bf59]CAUTION — Where these pages and an in-flight instrument disagree, the instrument is correct.[/color] The MFD [b]DOCK[/b] page carries the lane, the limits and the standing instruction actually in force; the MFD [b]MARKET[/b] page carries the prices actually offered. These pages record what was published.

[color=#66ccff]CONTENTS[/color]
[b]ARRIVAL[/b] ........ the lane and its plate, limits, clearance, traffic, the berth, and the arrival procedure
[b]DEPARTURE[/b] ...... the outbound procedure
[b]LOCAL NOTICES[/b] .. conditions on the claim, the schedule of prices, and the system chart""",
	},
	{
		"id": "lane",
		"group": "ARRIVAL",
		"title": "The approach lane",
		"body": """[color=#8c9eb8]HARBOUR CONTROL · TERMINAL PROCEDURES[/color]

The berth is flown for. A transit places a vessel on the outer approach; from that point the lane is hand-flown under the direction of Control.

[color=#66ccff]THE PLATE[/color]
Four markers lead inward through the structure, each with a ring to be flown through and a corridor about the leg approaching it.

Marker ..... Ring ...... Corridor
[b]ALPHA[/b] ...... 14 m ...... hold marker; the approach to it is free flight
[b]BRAVO[/b] ...... 12 m ...... 22 m
[b]CHARLIE[/b] .... 9 m ....... 15 m — the gap between two habitat drums
[b]DELTA[/b] ...... 6.5 m ..... 10 m — directly above the pad
[b]PAD[/b] ........ 7 m ....... 6 m — vertical descent into a walled bay

[color=#66ccff]THE FINAL DESCENT[/color]
The descent from DELTA is a funnel, not a tube. It is wide above the bay walls, where a vessel arrives carrying lateral speed and must establish a vertical descent, and narrows to 6 m once between the walls. Vessels are not held to the narrow figure until they are down among the structure.

[color=#66ccff]MARKERS[/color]
Each marker is to be crossed inside its ring, in order. A marker crossed outside its ring is a missed marker.""",
	},
	{
		"id": "limits",
		"group": "ARRIVAL",
		"title": "Limits & compliance",
		"body": """[color=#8c9eb8]HARBOUR CONTROL · TERMINAL PROCEDURES[/color]

[color=#66ccff]SPEED[/color]
Inbound to the hold .......... [b]22 m/s[/b]
Cleared, in the lane ......... [b]12 m/s[/b]
Final ........................ [b]6 m/s[/b]
Holding ...................... [b]3 m/s[/b]

Exceeding a limit draws a warning. Sustained for [b]2.5 seconds[/b] it is a go-around. Departure from the leg's corridor is allowed [b]1.2 seconds[/b] before the same.

[color=#66ccff]GO-AROUND[/color]
A go-around returns the vessel to the hold marker to be re-sequenced. It is the consequence of failing to comply with an instruction: excessive speed, leaving the corridor, a missed marker, loss of separation, or arriving at the final marker with the landing gear not down and locked or the cargo hatch open.

Standing with this operator is reduced for each go-around, subject to a limit per visit.

[color=#66ccff]CONTACT WITH THE STRUCTURE[/color]
Contact is not treated as a failure to comply, and does not cost the clearance. The harbour renders an account instead.

Charges comprise a [b]100 CR[/b] call-out together with the cost of repair, assessed on the severity of the impact, and a reduction in standing. Where the charge cannot be met in credits it is taken against standing.

A period of [b]5 seconds[/b] follows an impact in which the speed and corridor limits are not enforced, the deviation being attributable to the impact rather than to the pilot.

[color=#8c9eb8]NOTE — Damage to the vessel is a matter between the pilot and the vessel. The harbour charges only for its own structure.[/color]""",
	},
	{
		"id": "clearance",
		"group": "ARRIVAL",
		"title": "Clearance & traffic",
		"body": """[color=#8c9eb8]HARBOUR CONTROL · TERMINAL PROCEDURES[/color]

[color=#66ccff]CLEARANCE[/color]
Clearance to run the lane is requested at the hold marker. It is refused, with the reason stated, while:
· the vessel is still moving — it must be stopped below [b]3 m/s[/b];
· traffic occupies the lane ahead;
· sequencing is incomplete — a minimum of [b]5 seconds[/b] at the hold.

Control will call the clearance itself once the vessel is stopped and the lane is clear. The same control requests a clearance and reads back the standing instruction.

[color=#66ccff]TRAFFIC[/color]
Three vessels work this volume on their own schedules:
[b]LANE TUG BOLLARD[/b] ....... crosses the BRAVO–CHARLIE leg square on
[b]SHUTTLE MERIDIAN 9[/b] ..... the ring circuit
[b]ORE BARGE THRENODY[/b] ..... the outer transit, across the approach to the hold

All are solid and none will give way. An advisory is passed within [b]8 m[/b]. Separation below [b]2.5 m[/b] is a go-around.

Control may stop a cleared vessel in the lane when traffic crosses ahead of it. The hold speed applies while it does.

[color=#66ccff]AUTO-BERTH[/color]
On request, Control will fly the approach on a vessel's behalf. A handling charge of [b]300 CR[/b] is levied, together with a reduction in standing.

The service is refused once a vessel is on final, and refused where the charge cannot be met.""",
	},
	{
		"id": "berth",
		"group": "ARRIVAL",
		"title": "The berth & assessment",
		"body": """[color=#8c9eb8]HARBOUR CONTROL · TERMINAL PROCEDURES[/color]

[color=#66ccff]THE PAD[/color]
Deck markings are [b]7 m[/b] across. A vessel set down outside the markings has not made the berth and is returned to the pattern.

[color=#66ccff]ASSESSMENT OF ARRIVAL[/color]
An arrival is assessed on three counts and recorded against the vessel:

Sink rate ................ 50%
Position on the markings . 30%
Attitude ................. 20%

Recorded as [b]GREASED[/b] below 1.5 m/s, [b]FIRM[/b] below 3.0 m/s, or [b]HARD[/b] above it. A good arrival earns standing with this operator.

[color=#8c9eb8]NOTE — The harbour assesses arrivals; it does not certify them. What a vessel's landing gear will accept — sink rate, attitude and drift at contact — is published by her builder, and a pilot is expected to know it. See [b]Landing limitations[/b] in the ship's handbook.[/color]""",
	},
	{
		"id": "arrival-procedure",
		"group": "ARRIVAL",
		"title": "Arrival procedure",
		"body": """[color=#8c9eb8]HARBOUR CONTROL · TERMINAL PROCEDURES

The harbour's required sequence. The vessel's own configuration items — hatch, gear, camera and touchdown limits — are in her handbook under [b]Arrival[/b], and are flown alongside this.[/color]

[b]1  OUTER APPROACH[/b] — [color=#59f28c]ESTABLISHED[/color]
     [color=#8c9eb8]The transit ends here. The lane is flown from this point.[/color]
[b]2  MARKER ALPHA[/b] — [color=#59f28c]PROCEED AND HOLD[/color], below [b]3 m/s[/b]
     [color=#f2bf59]CAUTION — Clearance is refused while the vessel is moving. Establish the hold before requesting.[/color]
[b]3  CLEARANCE[/b] — [color=#59f28c]OBTAIN[/color] · {{act:dock_request}}
     [color=#8c9eb8]Refused while traffic occupies the lane, and withheld for a minimum of 5 seconds' sequencing. Each refusal states its cause.[/color]
[b]4  SPEED[/b] — [color=#59f28c]BELOW 12 m/s[/color] once cleared
[b]5  MARKERS[/b] — [color=#59f28c]BRAVO, CHARLIE, DELTA[/color] in order, through each ring
     [color=#8c9eb8]Corridors of 22 m, 15 m and 10 m. 1.2 seconds outside a corridor is a go-around.[/color]
[b]6  TRAFFIC[/b] — [color=#59f28c]GIVE WAY[/color]
     [color=#8c9eb8]Hold position when Control calls traffic across the lane.[/color]
[b]7  LANDING GEAR[/b] — [color=#59f28c]DOWN AND LOCKED BEFORE DELTA[/color]
     [color=#f2bf59]CAUTION — Arrival at the final marker with the gear not locked, or with a cargo hatch open, is a go-around.[/color]
[b]8  FINAL[/b] — [color=#59f28c]BELOW 6 m/s[/color] between the bay walls
[b]9  TOUCHDOWN[/b] — [color=#59f28c]INSIDE THE 7 m MARKINGS[/color]
     [color=#8c9eb8]The vessel's own limits at contact are her builder's — see her handbook.[/color]

[color=#8c9eb8]An approach may be abandoned at any point before touchdown; the vessel leaves the pattern and no berth is booked.[/color]""",
	},
	{
		"id": "departure-procedure",
		"group": "DEPARTURE",
		"title": "Departure procedure",
		"body": """[color=#8c9eb8]HARBOUR CONTROL · TERMINAL PROCEDURES

The harbour's required sequence outbound. The vessel's configuration items are in her handbook under [b]Departure[/b].[/color]

The lane is flown in reverse under the same corridor and speed discipline as an arrival. Only the order of the markers and the consequence of a failure differ.

[b]1  DEPARTURE HOLD[/b] — [color=#59f28c]ESTABLISHED ON THE PAD[/color]
     [color=#8c9eb8]Undocking lifts the vessel into the hold. It is not a release.[/color]
[b]2  DEPARTURE CLEARANCE[/b] — [color=#59f28c]OBTAIN[/color] · {{act:dock_request}}
     [color=#8c9eb8]Sequenced around the same traffic that governs an arrival, with the same minimum hold.[/color]
[b]3  LIFT OFF[/b] — [color=#59f28c]BELOW 6 m/s[/color] within the bay
[b]4  MARKERS[/b] — [color=#59f28c]DELTA, CHARLIE, BRAVO, ALPHA[/color] in order
     [color=#8c9eb8]Same rings and corridors as an arrival, below 12 m/s once clear of the bay.[/color]
[b]5  LANDING GEAR[/b] — [color=#59f28c]DOWN UNTIL DELTA IS CLEARED[/color]
     [color=#f2bf59]CAUTION — A leg remains within the bay walls until the final marker is behind you. Raising the gear before that point is a violation.[/color]
[b]6  GEAR[/b] — [color=#59f28c]STOWED BEFORE RELEASE[/color]
     [color=#8c9eb8]Control withholds the release from the pattern until the gear is stowed.[/color]

[color=#66ccff]FAILURE TO COMPLY, OUTBOUND[/color]
A broken rule on departure is recorded as a [b]reprimand[/b] — a reduction in standing and an urgent call — and not as a go-around. A departing vessel is leaving in any case, and returning it to the pad serves nobody.

Contact with the structure is charged for exactly as on arrival.""",
	},
	{
		"id": "claim",
		"group": "LOCAL NOTICES",
		"title": "Claim conditions",
		"body": """[color=#8c9eb8]CLAIM OFFICE · NOTICE TO SALVORS, CLAIM 7741-C[/color]

Conditions on this claim are set by its operator and are subject to change. This notice describes how others in the volume will behave around a hull being worked. It says nothing about the working of the hull itself, which is a matter for the vessel's own handbook.

[color=#66ccff]RIVAL CUTTERS[/color]
A rival cutter arrives between [b]45 and 90 seconds[/b] after a vessel reaches station, from a range of about 180 m. It works the derelict from its own standoff and severs a member at intervals of approximately [b]25 seconds[/b].

[color=#f2705c]WARNING — Severed pieces are unclaimed property and title passes on recovery.[/color] A rival will recover pieces cut by another vessel. It requires 6 m and 2 seconds to do so.

[color=#66ccff]ENFORCEMENT[/color]
This claim is held by [b]FREEHOLD[/b]. A patrol arrives between [b]4 and 6 minutes[/b] after a vessel reaches station, closing at 15 m/s from a range of 400 m. Warnings are broadcast at two minutes and at thirty seconds.

A vessel detected within the enforcement range is fined [b]200 CR[/b] and loses 0.12 standing with Freehold. The penalty is levied once per visit.

Enforcement range is [b]60 m[/b], scaled by the vessel's signature to passive detection. A vessel running with reduced emissions must be approached correspondingly closer before it can be acted upon — at half signature, 30 m; at a quarter, 15 m.

[color=#8c9eb8]NOTE — How a vessel reduces its signature is a matter for its own handbook.[/color]

[color=#66ccff]ABANDONED SALVAGE[/color]
Pieces left adrift when a vessel vacates the claim are abandoned and revert to the operator. A vessel returning to this claim is assigned a fresh derelict.""",
	},
	{
		"id": "prices",
		"group": "LOCAL NOTICES",
		"title": "Schedule of prices",
		"body": """[color=#8c9eb8]COMMERCIAL AGENT · SCHEDULE OF REFERENCE PRICES[/color]

Reference prices only. The offer actually made is adjusted by the buying operator and by the standing of the vessel, and is displayed on the MFD [b]MARKET[/b] page at the berth.

[color=#66ccff]COMMODITIES[/color]
Commodity ............. Reference ..... Mass ....... Volume
[b]INTACT NAV CORES[/b] ..... 1250 CR/EA .... 0.8 t ...... 0.6 m³
[b]HULL ALLOY[/b] ........... 410 CR/T ...... 1.0 t ...... 0.9 m³
[b]RARE ISOTOPES[/b] ........ 228 CR/G ...... negligible . negligible
[b]FUSED OPTICS[/b] ......... 95 CR/KG ...... 0.001 t .... 0.004 m³
[b]VOLATILES[/b] ............ 62 CR/T ....... 1.0 t ...... 1.4 m³

[color=#8c9eb8]NOTE — Mass and volume are given because a hold is limited in both. Volatiles occupy more space per unit of value than any other commodity listed; nav cores and isotopes occupy very little.[/color]

[color=#66ccff]BUYERS[/color]
[b]FREEHOLD[/b] — operator of this claim. Pays above reference for hull alloy and volatiles, below it for isotopes.
[b]LAGRANGE UNION[/b] — pays above reference for nav cores and fused optics.
[b]MERIDIAN CO.[/b] — pays above reference for rare isotopes, and well for nav cores.

[color=#66ccff]TERMS[/color]
A hold is disposed of entire, at the berth, at the buying operator's prices. Cargo is not bought by the item and nothing is offered for sale to vessels — no fuel, no repair, no berthing charge, no consumables.

[color=#66ccff]STANDING[/color]
Standing with an operator moves the offer across a span of [b]0.85 to 1.15[/b] of the reference price, and is therefore worth money.

It rises with each disposal. It is reduced by a patrol fine, by use of auto-berth, by contact with harbour structure, and by repeated go-arounds.""",
	},
	{
		"id": "chart",
		"group": "LOCAL NOTICES",
		"title": "System chart",
		"body": """[color=#8c9eb8]SYSTEM CHART · REFERENCE ONLY[/color]

The [b]HEARTH[/b] system, as presented on a vessel's Tactical [b]CHART[/b] mode. Primary: a K2V star.

Body ............... Distance
[b]CINDER[/b] ............. 0.18 AU
[b]BASTION[/b] ............ 0.34 AU
[b]VERGE[/b] .............. 0.52 AU
[b]THALASSA[/b] ........... 0.95 AU — moons KERUL, HAVEN, LOWLIGHT
[b]PALINODE[/b] ........... 1.60 AU — moons TARSA, GREYWATER
[b]COLDHARBOR A/B[/b] ..... 3.2 AU — binary pair

[color=#f2bf59]CAUTION — This is not a navigation document.[/color] Own-ship position is not plotted. The marker shown is the claim's filed position and does not move with the vessel.

[color=#8c9eb8]NOTE — Transits between a claim and a berth's outer approach are flown by the vessel without reference to this chart. It carries no route, clearance or separation information.[/color]""",
	},
]
