use econ::sim::*; use econ::world::*;
fn main(){ for d in [2u32,5,10,30,60]{ let (w,_)=simulate(Config{seed:3,..Config::default()},d,&[]);
 let pl:u64=w.players.values().map(|p|p.pts).sum(); let mc:Vec<u64>=w.merchants.iter().map(|m|m.cash).collect();
 let ms:u32=w.merchants.iter().map(|m|m.stock.values().sum::<u32>()).sum(); let ps:u32=w.players.values().map(|p|p.stock.values().sum::<u32>()).sum();
 println!("d{d} players {pl} merchants {mc:?} treasury {} mstock {ms} pstock {ps} idx {}",w.treasury,w.price_index_bp()); } }
