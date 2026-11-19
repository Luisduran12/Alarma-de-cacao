import { envolverSeguro } from "../src/http.js";
import { clienteIADelEntorno, dependenciasDelEntorno } from "../src/entorno.js";
import { crearFoto } from "../src/foto.js";

export default {
  fetch: envolverSeguro((request: Request) => crearFoto({ ...dependenciasDelEntorno(), ia: clienteIADelEntorno() })(request), "analizar-foto"),
};
