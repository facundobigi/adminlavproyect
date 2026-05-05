String normalizarPatente(String value) {
  return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

bool patenteValida(String value) {
  final normalized = normalizarPatente(value);
  return normalized.length >= 4 && normalized.length <= 10;
}

const patenteHint = 'Ej: AB123CD, ABC1D23 o ABC1234';
const patenteError =
    'Formato invalido: usa 4 a 10 letras/numeros, con espacios o guiones opcionales';
