// Independent unit conversions from primary definitions (NIST SP 811 /
// exact SI definitions), for VALIDATION.md VC-17. No engine imports.
library;

const double lbToKg = 0.45359237; // exact
const double inToM = 0.0254; // exact
const double ftToM = 0.3048; // exact
const double psiToPa = lbToKg * 9.80665 / (inToM * inToM); // 6894.757293...
const double btuToJ = 1055.05585262; // IT Btu
const double gallonToM3 = 231 * inToM * inToM * inToM; // US gallon, exact
const double barrelToM3 = 42 * gallonToM3; // 0.158987294928
const double inH2OToPa = 249.0889; // conventional (4 °C) value used by the spec

double kToC(double k) => k - 273.15;
double kToF(double k) => k * 9 / 5 - 459.67;
double paToBar(double pa) => pa / 1e5;
double paToPsia(double pa) => pa / psiToPa;
double molsToKmolh(double v) => v * 3.6;
double molsToLbmolh(double v) => v * 3600 / (lbToKg * 1000);
double wToKw(double w) => w / 1000;
double wToMmbtuh(double w) => w * 3600 / (btuToJ * 1e6);
double m3hToBblD(double v) => v / 3600 * 86400 / barrelToM3;
double bblDToM3h(double v) => v * barrelToM3 / 86400 * 3600;
double mToMm(double m) => m * 1000;
double mToIn(double m) => m / inToM;
double kgm3ToLbft3(double v) => v / (lbToKg / (ftToM * ftToM * ftToM));
double deltaKToDeltaF(double v) => v * 1.8;
