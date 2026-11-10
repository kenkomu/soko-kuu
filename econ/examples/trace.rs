use econ::sim::*; use econ::world::*;
fn main(){ for d in [8u32,9,10,11,12,16,20]{ let (w,_)=simulate(Config{seed:3,random_events:false,..Config::default()},d,&[]);
 let m=&w.merchants[2]; println!("d{d} cash {} stock {:?} treasury {} ev {}",m.cash,m.stock.values().collect::<Vec<_>>(),w.treasury,w.events.len()); } }
