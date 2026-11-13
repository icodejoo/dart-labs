declare namespace wasm_bindgen {
    /* tslint:disable */
    /* eslint-disable */

    export class WorkerPool {
        free(): void;
        [Symbol.dispose](): void;
        static new(initial?: number | null, script_src?: string | null, worker_js_preamble?: string | null, wasm_bindgen_name?: string | null): WorkerPool;
        /**
         * Creates a new `WorkerPool` which immediately creates `initial` workers.
         *
         * The pool created here can be used over a long period of time, and it
         * will be initially primed with `initial` workers. Currently workers are
         * never released or gc'd until the whole pool is destroyed.
         *
         * # Errors
         *
         * Returns any error that may happen while a JS web worker is created and a
         * message is sent to it.
         */
        constructor(initial: number, script_src: string, worker_js_preamble: string, wasm_bindgen_name: string);
    }

    export function frb_dart_fn_deliver_output(call_id: number, ptr_: any, rust_vec_len_: number, data_len_: number): void;

    /**
     * # Safety
     *
     * This should never be called manually.
     */
    export function frb_dart_opaque_dart2rust_encode(handle: any, dart_handler_port: any): number;

    export function frb_dart_opaque_drop_thread_box_persistent_handle(ptr: number): void;

    export function frb_dart_opaque_rust2dart_decode(ptr: number): any;

    export function frb_get_rust_content_hash(): number;

    export function frb_pde_ffi_dispatcher_primary(func_id: number, port_: any, ptr_: any, rust_vec_len_: number, data_len_: number): void;

    export function frb_pde_ffi_dispatcher_sync(func_id: number, ptr_: any, rust_vec_len_: number, data_len_: number): any;

    /**
     * ## Safety
     * This function reclaims a raw pointer created by [`TransferClosure`], and therefore
     * should **only** be used in conjunction with it.
     * Furthermore, the WASM module in the worker must have been initialized with the shared
     * memory from the host JS scope.
     */
    export function receive_transfer_closure(payload: number, transfer: any[]): void;

    export function wasm_start_callback(): void;

}
declare type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

declare interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly __wbg_workerpool_free: (a: number, b: number) => void;
    readonly frb_dart_fn_deliver_output: (a: number, b: any, c: number, d: number) => void;
    readonly frb_dart_opaque_dart2rust_encode: (a: any, b: any) => number;
    readonly frb_dart_opaque_drop_thread_box_persistent_handle: (a: number) => void;
    readonly frb_dart_opaque_rust2dart_decode: (a: number) => any;
    readonly frb_get_rust_content_hash: () => number;
    readonly frb_pde_ffi_dispatcher_primary: (a: number, b: any, c: any, d: number, e: number) => void;
    readonly frb_pde_ffi_dispatcher_sync: (a: number, b: any, c: number, d: number) => any;
    readonly frb_rust_vec_u8_free: (a: number, b: number) => void;
    readonly frb_rust_vec_u8_new: (a: number) => number;
    readonly frb_rust_vec_u8_resize: (a: number, b: number, c: number) => number;
    readonly receive_transfer_closure: (a: number, b: number, c: number, d: number) => void;
    readonly wasm_start_callback: () => void;
    readonly workerpool_new: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => void;
    readonly workerpool_new_raw: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => void;
    readonly __wasm_bindgen_func_elem_520: (a: number, b: number, c: any) => void;
    readonly __wasm_bindgen_func_elem_527: (a: number, b: number) => void;
    readonly __wbindgen_export: (a: number, b: number) => number;
    readonly __wbindgen_export2: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_export3: (a: number, b: number, c: number) => void;
    readonly __wbindgen_export4: (a: number) => void;
    readonly __wbindgen_export5: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_export6: (a: number, b: number) => void;
    readonly __wbindgen_add_to_stack_pointer: (a: number) => number;
    readonly __wbindgen_export7: (a: number, b: number) => void;
    readonly __wbindgen_export8: (a: number) => void;
    readonly __wbindgen_start: () => void;
}

declare type SyncInitInput = BufferSource | WebAssembly.Module;

declare namespace wasm_bindgen {
    /**
     * Instantiates the given `module`, which can either be bytes or
     * a precompiled `WebAssembly.Module`.
     *
     * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
     *
     * @returns {InitOutput}
     */
    export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;
}

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
declare function wasm_bindgen (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
