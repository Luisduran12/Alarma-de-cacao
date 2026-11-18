import { crearChat } from "../src/chat.js";
import { clienteIADelEntorno, dependenciasDelEntorno } from "../src/entorno.js";

export default {
  fetch: (request: Request) => crearChat({ ...dependenciasDelEntorno(), ia: clienteIADelEntorno() })(request),
};
