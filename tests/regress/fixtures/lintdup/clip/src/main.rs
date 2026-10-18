fn main() {
    let x = std::env::args().count() > 1;
    if x == true {
        println!("yes");
    }
}
