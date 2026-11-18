import { dependenciasDelEntorno } from "../src/entorno.js";
import { crearLugar } from "../src/lugar.js";

export default {
  fetch: (request: Request) => crearLugar(dependenciasDelEntorno())(request),
};
