import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/app/format.dart';

void main() {
  test('prices use Indian digit grouping', () {
    expect(Fmt.price(540), '₹540');
    expect(Fmt.price(1100), '₹1,100');
    expect(Fmt.price(2200.0), '₹2,200');
    expect(Fmt.price(150000), '₹1,50,000');
    expect(Fmt.price(12345678), '₹1,23,45,678');
    expect(Fmt.price(540.5), '₹540.50');
  });

  test('price range across seat classes', () {
    expect(Fmt.priceRange([540, 580, 560]), '₹540–580');
    expect(Fmt.priceRange([750, 1490, 770]), '₹750–1,490');
    expect(Fmt.priceRange([540, 540]), '₹540');
    expect(Fmt.priceRange(const <num>[]), isNull);
  });
}
