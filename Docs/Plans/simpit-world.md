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

## Ship Performance: Why Ships Fly to a Limit

- **There is no universal speed limit, and there never was one.** An earlier
  draft of this setting had one — a "Higgs drag" that grew with velocity, so a
  hull's ceiling was where its thrust and that drag balanced. It has been
  removed. It made speed an *absolute* quantity in a universe where velocity is
  relative, which falls apart the moment the setting acquires anything with real
  orbital mechanics around it: a body the size of Earth has things moving at
  kilometres per second, relative to it, quite normally.
- **What limits a ship is her flight computer.** Every hull carries a
  **governor** — a fly-by-wire limit the pilot sets, holding the ship to a chosen
  speed. It is a piece of equipment, not a law of nature, and it can be switched
  off. That is the whole of it.
- **A governor names its reference, which is why it survives contact with a
  planet.** It holds a speed *relative to whatever the navigation system is
  referenced to* — the berth you are approaching, the derelict you are cutting,
  the body you are in orbit around. Near a planet it governs your closing speed
  on the thing you are flying at, which is the number that actually matters and
  the only one that means anything. Change what the instruments are referenced
  to and you change what the governor is holding you to.
- **Switching it off is a real decision with real consequences.** Under direct
  law nothing limits the ship at all, and nothing will stop her but the pilot and
  the propellant. Reverse thrust is a fraction of forward, so arresting a high
  speed means turning the ship around and burning — which takes room, time and
  mass you may not have budgeted.
- **What a drive buys is thrust, not speed.** The stages differ in how hard they
  push, what they cost the bus, and what they consume. None of them sets a
  maximum speed, because nothing does. A better drive gets you to a speed sooner
  and stops you from it sooner; it does not raise a ceiling, because there is no
  ceiling.
- **Mass is the other half of performance, and it is live.** Acceleration is
  thrust over all-up weight, so a full hold and full tanks are felt on every axis
  — slower to accelerate, slower onto a commanded rotation rate, slower to stop
  at one, and carrying more momentum into anything you hit. A salvager's ship
  handles worst exactly when she is carrying the most, which is the trade the
  whole job is built on.
- **Heat is real and governs efficiency, not speed.** Waste heat is why hulls
  carry radiator fins, and it stays a live constraint on **battery efficiency,
  alternator efficiency, life support, sensor operation, cutter operation** and
  on whatever systems come later. (Nothing in the simulation models heat yet; it
  is written down here so the hooks exist when they are wanted, and it
  deliberately carries no figures until something enforces them.)
- **Reverse is deliberately weak.** No yard designs a drive to push backward as
  hard as forward — reverse thrust is a braking/manoeuvring tap off the main
  drive, not a mirrored engine. A ship's reverse performance is a small fraction
  of its forward performance, full stop.

## Power and Propulsion

- **A fusion reactor is the ship's one energy source, and it sells two different
  products.** An **alternator** converts part of its output into electricity for
  the bus; the remainder leaves as **heat**, and the heat is what the
  nuclear-thermal stage expands hydrogen with. That division is the causal reason
  the thermal stage costs the bus almost nothing while the field stage is
  expensive — they are drawing on different products of the same reactor, and a
  ship's electrical capacity and its thermal-drive capacity are set by how the
  one reactor is divided between them. A **battery** buffers the difference
  between what the alternator makes and what the ship is drawing. Alternator off
  and you are running on the battery; battery off and you are limited to whatever
  the alternator is making at that instant; both off and the ship is quiet.
- **The drive is a hybrid** of a Mass-Effect / photonic / electrodynamic **field
  stage** — reactionless, propellant-free, and electrically expensive — and two
  reaction stages layered on top of it.
- **Nuclear thermal.** Liquid hydrogen heated by the fusion reactor and expelled.
  Real thrust, real reaction mass, and almost no load on the bus, because it runs
  on the reactor's heat rather than its amps.
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
