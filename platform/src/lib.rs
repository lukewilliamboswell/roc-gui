#![allow(unused)]

mod graphics;
mod gui;
mod roc;

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    let bounds = roc_app::Bounds {
        width: 1900.0,
        height: 1000.0,
    };

    let main_for_host = roc_app::mainForHost();

    dbg!(&main_for_host);

    let mut model = main_for_host.init.force_thunk(bounds);

    // let tick = std::time::Duration::from_secs(1);
    // let tick_event = roc_app::Event::Tick(u64::try_from(tick.as_millis()).unwrap()); 
       
    // model = main_for_host.update.force_thunk(&mut model, tick_event);

    let elem = main_for_host.render.force_thunk(&mut model); 

    dbg!(elem);

    // gui::run_event_loop("RocOut!", bounds).expect("Error running event loop");

    // Exit code
    0
}
