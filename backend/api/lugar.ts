import { envolverSeguro } from "../src/http.js";
import { dependenciasDelEntorno } from "../src/entorno.js";
import { crearLugar } from "../src/lugar.js";

export default {
  fetch: envolverSeguro((request: Request) => crearLugar(dependenciasDelEntorno())(request), "lugar"),
};
