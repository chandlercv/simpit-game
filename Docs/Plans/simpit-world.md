# Simpit Game World

## Same Humanity

### Time

#### After a Big War

- Economic/logistics component of the conflict
  - Commerce raiders
    - What produced so much to salvage

**Why the salvage is there, stated plainly.** The totalitarians did not value or
honour their logistical chain, and they over-valued their "warrior" class. That
one attitude produced all three of their characteristic failures: they
over-emphasized the attack, under-emphasized sensors and observation, and
**under-protected their transports**. The under-protected transports are the
reason there is so much good salvage to be had — a war's worth of freighters,
tenders and their escorts killed on routes nobody was defending properly, and
still out there. The premise of the whole trade is a logistics failure, not a
battle.

#### Struggle Between Totalitarian vs. Democracy

- Echoes of World War Two and Ukraine
- Democrat tactics
  - Personal, small, cheap weapons
  - Lots of probes and sensors
  - Operated remotely
  - Protected supply routes
    - Used sensors and detection to protect
  - Learned quickly from enemies
- Totalitarian tactics
  - Emphasized large, heavily armored, heavily armed weapons
  - Did not emphasize sensors or observation
  - Did not effectively defend supply routes
  - Did not learn quickly from enemies

Corporatists are emerging, but there's still room for independents to make a good living.

## System Basics

- **Host star:** K-dwarf — cooler and longer-lived than the Sun, giving a wide, stable habitable zone and billions of extra years for a civilization to actually run a terraforming program
- **Overall layout:** rocky worlds close in, multiple gas giants spaced through/near the habitable zone, dwarf planets and belts further out

## Rocky Planets (Inner System)

- A scorched, airless innermost world — too close for anything but mining outposts
- A Venus-analog: rocky, roughly habitable-zone-adjacent, but a runaway greenhouse makes it another handwaved terraforming target rather than natively habitable
- One naturally habitable rocky world in the classic zone — the "homeworld," Earth-analog, no terraforming needed
- Optionally, a Mars-analog just outside the zone — thin atmosphere, partially terraformed, common frontier/colony setting

## Gas Giants

- 2-3 giants, spaced at least ~3.5 mutual Hill radii apart to keep their orbits dynamically stable over geological time
- Each giant selected/tuned to have a modest magnetosphere (Saturn-like, not Jupiter-like) to keep radiation survivable near its moons
- Each hosts a system of moons, at least a couple of which are Titan-class or larger — necessary mass threshold to hold onto a terraformed atmosphere long-term

## Habitable Moons

- Chosen specifically for either (a) orbiting far enough out to sit outside the worst of their giant's radiation belts (a Callisto-style position), or (b) being protected by in-universe shielding infrastructure the terraformers built — gives every habitable moon an actual engineering reason for being survivable, not just narrative convenience
- Some moons close to their giant run warm via tidal heating (Io/Europa-style flexing) — a legitimate physics reason a moon works even if it's on the outer edge of or outside the star's habitable zone

## Dwarf Planets / Frontier Bodies

- Scattered further out, on eccentric orbits — some as binary dwarf-planet pairs (a Pluto-Charon-style setup) with a real, open-space barycenter between them
- Serve as the "wild frontier" tier of the setting — less infrastructure, weirder navigation routes

## Navigation Mechanic

*No hardware — folds occur at geometrically real points.*

- **Inter-moon L1 points** — the gravitational saddle point between any two moons of the same giant; forms a natural "necklace" of nodes connecting all of that giant's moons, shifting predictably as the moons orbit
- **Orbital nodes** — where a moon's inclined orbit crosses a shared reference plane; where multiple moons' nodes cluster, you get natural multi-moon hub junctions
- **Empty orbital foci** — the geometrically real but massless second focus of an eccentric orbit; useful for frontier dwarf-planet routes, since it's real orbital mechanics but narratively fresher than Lagrange points
- **Resonance conjunction windows** — for moons in mean-motion resonance (Galilean-moon style), periodic alignments create time-gated fold windows rather than fixed points — adds a scheduling/strategy layer
- **Trojan L4/L5 points** — stable, no station-keeping needed, but real debris accumulation makes them double as hazard/resource zones (salvage, mining) rather than clean travel nodes

**Net effect:** "core" travel between well-mapped moons uses L1 necklaces and orbital nodes; "frontier" travel to dwarf planets uses foci and resonance timing — two different navigation feels for two different tiers of space, both grounded in real orbital mechanics.

Travel between planetary systems requires far more energy than an individual ship can provide — it's very expensive and happens on roughly a once-a-century timescale.

## Ship Performance: Why There's a Speed Ceiling

- **Higgs drag, not waste heat.** The Higgs field is the one frame everything is
  ultimately referred to. At ordinary speeds a hull's coupling to it is just the
  familiar mass term. Push harder and the coupling grows with velocity and
  behaves like a drag. A ship's ceiling is simply the speed at which its thrust
  and that drag balance.
- **The compact fusion reactor is why anyone ever notices.** This is the causal
  claim, and everything else follows from it: *without the reactor at the heart
  of the ship, the Higgs interaction would never be limiting at these speeds.*
  Running a compact fusion containment makes the coupling enormously more
  observable — the ship drags against the field because of what it is carrying,
  not because of how it is shaped. Every ship with one of these reactors has a
  ceiling, and the ceiling is a property of **the reactor**, not of the airframe.
  (It is also why a ceiling exists at all in a vacuum, which a plain "drag" story
  never explains.)
- **Salvage hulls still run below a purpose-built ceiling.** A salvager flies a
  reactor pulled out of somebody else's ship, and she sits wherever that reactor
  sits. That is the in-fiction reason a player ship feels sluggish next to the
  military-surplus wrecks she is cutting apart, and it makes the upgrade path a
  better-matched reactor rather than a bigger engine.
- **Carrying propellant is how you beat the ceiling.** The drag-limited maximum
  is what a *field* drive can do: it is pushing against the coupling and losing.
  A drive that throws real reaction mass out of the back is adding momentum
  instead of fighting the coupling, so it can sit above the field drive's
  terminal velocity for exactly as long as the mass lasts. That is why propellant
  is spent rather than allocated.
- **Heat is still real — it just governs efficiency, not speed.** Waste heat is
  why hulls carry radiator fins, and it stays a live constraint on **battery
  efficiency, alternator efficiency, life support, sensor operation, cutter
  operation** and on whatever systems come later. It is simply not what caps a
  ship's speed. (Nothing in the simulation models heat yet; it is written down
  here so the hooks exist when they are wanted, and it deliberately carries no
  figures until something enforces them.)
- **Reverse is deliberately weak.** No yard designs a drive to push backward as
  hard as forward — reverse thrust is a braking/manoeuvring tap off the main
  drive, not a mirrored engine. A ship's reverse performance is a small fraction
  of its forward performance, full stop.

## Power and Propulsion

- **A fusion reactor is the ship's one energy source.** An **alternator** turns
  its output into electricity for the bus; a **battery** buffers the difference
  between what the alternator makes and what the ship is drawing. Alternator off
  and you are running on the battery; battery off and you are limited to whatever
  the alternator is making at that instant; both off and the ship is quiet.
- **The drive is a hybrid** of a Mass-Effect / photonic / electrodynamic **field
  stage** — reactionless, propellant-free, and electrically expensive — and two
  reaction stages layered on top of it.
- **Nuclear thermal.** Liquid hydrogen heated by the fusion reactor and expelled.
  Real thrust, real reaction mass, a ceiling above the field drive's, and almost
  no load on the bus, because it runs on the reactor's heat rather than its amps.
- **Combustion.** Liquid oxygen burned with the same liquid hydrogen in a
  conventional bipropellant chamber. The most thrust and the shortest endurance —
  a boost, not a cruise. Oxygen is useless without hydrogen to burn it with.
- **The stages are selected, not automatic.** A five-position selector picks
  which are running, and nothing steps in for a stage the pilot did not select:
  on the thermal stage alone, an empty hydrogen tank means no thrust at all until
  the pilot selects the field stage. Running dry never strands a ship, but it does
  not fly her home by itself either.
- **The hydrogen ramjet** is the intake that feeds the thermal stage. At the
  densities in this system it scavenges far too little to matter, which is why
  hydrogen is bought and carried rather than collected.

## WWII (Reference)

### Totalitarians

- Lacked native raw materials
- Needed to win fast
- Technical edge at the beginning
- Slow to learn from mistakes
  - Only one mind attacked a problem at a time
- Focus on "warrior" ethos
  - Repair/damage control suffered
  - Logistics suffered

### Democrats

- Needed to get manufactured arms and food to people across vulnerable routes

## Ukraine (Reference)

### Totalitarians

- Had quantities

### Democrats

- Adapted personal-sized weapons to punch way above their class
