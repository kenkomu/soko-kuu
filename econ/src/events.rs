//! Radio Soko events: ukame (drought), fuel, road, festival, harvest, glut.
use crate::pricing::*;
use crate::rng::Rng;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
#[serde(rename_all = "snake_case")]
pub enum EventKind { Ukame, Fuel, Road, Festival, Harvest, Glut }

pub const ALL_KINDS: [EventKind; 6] = [
    EventKind::Ukame, EventKind::Fuel, EventKind::Road, EventKind::Festival, EventKind::Harvest, EventKind::Glut,
];

/// An event with a magnitude in percent (1..=100).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "borsh", derive(borsh::BorshSerialize, borsh::BorshDeserialize))]
pub struct Event {
    pub kind: EventKind,
    pub day: u32,
    pub magnitude: u32,
}

impl Event {
    pub fn new(kind: EventKind, day: u32, magnitude: u32) -> Self { Event { kind, day, magnitude: magnitude.clamp(1, 100) } }
    pub fn duration(&self) -> u32 {
        match self.kind { EventKind::Ukame => 6, EventKind::Fuel => 5, EventKind::Road => 3, EventKind::Festival => 2, EventKind::Harvest => 5, EventKind::Glut => 3 }
    }
    pub fn active(&self, day: u32) -> bool { day >= self.day && day < self.day + self.duration() }
    /// Glut hits one good, chosen deterministically from the start day.
    pub fn glut_good(&self) -> usize { self.day as usize % GOODS.len() }
    pub fn text(&self) -> String {
        let m = self.magnitude;
        match self.kind {
            EventKind::Ukame => format!("Ukame: the rains have failed. Farm produce will cost about {}% more and arrive slowly.", m / 2),
            EventKind::Fuel => String::from("Fuel prices are up. Transport costs lift every price a little, charcoal and fish most."),
            EventKind::Road => String::from("The main road is cut by floods. Deliveries are late and stalls run low."),
            EventKind::Festival => format!("Festival this week: buyers are everywhere and prices run about {}% higher.", m / 2),
            EventKind::Harvest => format!("Harvest is in. Farm produce is arriving fast and prices ease by about {}%.", m / 2),
            EventKind::Glut => format!("A glut of {} floods the market. Sellers are cutting prices.", GOODS[self.glut_good()].id),
        }
    }
}

/// Combined modifiers for good `gi` on `day` from all events.
pub fn modifiers(events: &[Event], day: u32, gi: usize) -> Modifiers {
    let g = &GOODS[gi];
    let mut m = Modifiers::neutral();
    for e in events.iter().filter(|e| e.active(day)) {
        let mag = e.magnitude as u64;
        let (price_up, price_down, restock_up, restock_down, line): (u64, u64, u64, u64, String) = match e.kind {
            EventKind::Ukame if g.farm => (mag / 2, 0, 0, mag / 2, format!("Ukame (drought) cuts {} supply.", g.id)),
            EventKind::Fuel => {
                let p = if g.farm { mag / 5 } else { mag / 2 };
                (p, 0, 0, 0, format!("Fuel costs add about {}% to {}.", p, g.id))
            }
            EventKind::Road => (mag / 4, 0, 0, mag.min(90), "The cut road delays deliveries.".to_string()),
            EventKind::Festival => (mag / 2, 0, 0, 0, "Festival crowds push demand up.".to_string()),
            EventKind::Harvest if g.farm => (0, mag / 2, mag, 0, format!("Harvest season: {} is arriving in bulk.", g.id)),
            EventKind::Glut if e.glut_good() == gi => (0, mag / 2, mag, 0, format!("A glut of {} pushes its price down.", g.id)),
            _ => continue,
        };
        m.price_bp = m.price_bp * (100 + price_up) / 100 * (100 - price_down.min(60)) / 100;
        m.restock_bp = m.restock_bp * (100 + restock_up) / 100 * (100 - restock_down.min(90)) / 100;
        m.why.push(line);
    }
    m.price_bp = m.price_bp.clamp(BP / 3, BP * 3);
    m
}

/// Random event generation: about one event every 4 days, deterministic from `rng`.
pub fn maybe_spawn(rng: &mut Rng, day: u32) -> Option<Event> {
    if rng.below(100) < 25 {
        let kind = ALL_KINDS[rng.below(6) as usize];
        let mag = rng.range(15, 70) as u32;
        Some(Event::new(kind, day, mag))
    } else { None }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ukame_hits_farm_only() {
        let ev = [Event::new(EventKind::Ukame, 1, 40)];
        let tomato = modifiers(&ev, 2, 0);
        let fish = modifiers(&ev, 2, 4);
        assert!(tomato.price_bp > BP && tomato.restock_bp < BP);
        assert_eq!(fish, Modifiers::neutral());
        assert_eq!(modifiers(&ev, 20, 0), Modifiers::neutral());
    }
    #[test]
    fn harvest_lowers_price() {
        let m = modifiers(&[Event::new(EventKind::Harvest, 0, 50)], 1, 1);
        assert!(m.price_bp < BP && m.restock_bp > BP && !m.why.is_empty());
    }
    #[test]
    fn extremes_bounded() {
        let ev: Vec<_> = ALL_KINDS.iter().map(|k| Event::new(*k, 0, 100)).collect();
        for gi in 0..GOODS.len() { let m = modifiers(&ev, 1, gi); assert!(m.price_bp <= BP * 3 && m.price_bp >= BP / 3); }
    }
    #[test]
    fn serde_kind() { assert_eq!(serde_json::to_string(&EventKind::Ukame).unwrap(), "\"ukame\""); }
}
