import { clienteIADelEntorno, dependenciasDelEntorno } from "../src/entorno.js";
import { crearFoto } from "../src/foto.js";

export default {
  fetch: (request: Request) => crearFoto({ ...dependenciasDelEntorno(), ia: clienteIADelEntorno() })(request),
};
