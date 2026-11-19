import { crearChat } from "../src/chat.js";
import { envolverSeguro } from "../src/http.js";
import { clienteIADelEntorno, dependenciasDelEntorno } from "../src/entorno.js";

export default {
  fetch: envolverSeguro((request: Request) => crearChat({ ...dependenciasDelEntorno(), ia: clienteIADelEntorno() })(request), "chat"),
};
