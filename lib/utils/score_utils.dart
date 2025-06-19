// Ok dizisinden toplam puan hesaplar. X (yani -1 veya 11) için 10 puan sayılır.
int calculateSeriesTotal(List<int> arrows) {
  return arrows.fold(0, (sum, arrow) => sum + ((arrow == -1 || arrow == 11) ? 10 : arrow));
}
