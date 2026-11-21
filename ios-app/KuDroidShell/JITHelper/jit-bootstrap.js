// Serve executable-region requests from the attached process.
(function () {
    "use strict";
    const page = 16384n;
    const incrementalPreparation = 0x4b444a495443484bn;
    function packet(command) {
        const reply = send_command(command);
        if (!reply || /^E[0-9a-f]{2}(?:;|$)/i.test(reply)) throw new Error("Debugger command failed: " + command.split(",")[0]);
        return reply;
    }
    function hex(value) { return value.toString(16); }
    function decode(bytes) {
        if (!/^(?:[0-9a-f]{2})+$/i.test(bytes)) throw new Error("Invalid debugger register.");
        let value = 0n;
        for (let i = bytes.length - 2; i >= 0; i -= 2) value = (value << 8n) | BigInt("0x" + bytes.slice(i, i + 2));
        return value;
    }
    function encode(value) {
        let result = "";
        for (let i = 0; i < 8; ++i) { result += Number(value & 255n).toString(16).padStart(2, "0"); value >>= 8n; }
        return result;
    }
    function write(register, value) {
        if (packet("P" + register + "=" + encode(value)) !== "OK") throw new Error("Could not update debugger register.");
    }
    let stopped = packet("vAttach;" + Number(get_pid()).toString(16));
    let attached = true;
    let initialStop = true;
    let pendingPC = null;
    try {
        log("JIT_ATTACHED");
        while (true) {
            const stopLabel = (initialStop ? "attach:" : "request:") + stopped.slice(0, 3);
            log("JIT_STOP:" + stopLabel);
            const stop = /^[TS]([0-9a-f]{2})/i.exec(stopped);
            const signal = stop ? parseInt(stop[1], 16) : -1;
            // Accept the initial debugger suspension without masking later faults.
            if (signal !== 5 && !(initialStop && signal === 17)) {
                throw new Error("Unexpected process stop during JIT setup (" + stopLabel + ").");
            }
            const field = /(?:^|;)thread:([^;]+);/.exec(stopped.slice(3));
            const current = field ? null : /^QC((?:p[0-9a-f]+\.)?[0-9a-f]+)$/i.exec(packet("qC"));
            const thread = field ? field[1] : current && current[1];
            if (!thread || !/^(?:p[0-9a-f]+\.)?[0-9a-f]+$/i.test(thread) || packet("Hg" + thread) !== "OK") {
                throw new Error("Could not select the stopped thread.");
            }
            const pc = decode(packet("p20"));
            const instruction = decode(packet("m" + hex(pc) + ",4"));
            if ((instruction & 0xffe0001fn) !== 0xd4200000n || ((instruction >> 5n) & 65535n) !== 61453n) {
                if (initialStop) { initialStop = false; stopped = packet("c"); continue; }
                throw new Error("Unexpected breakpoint during JIT setup.");
            }
            initialStop = false;
            pendingPC = pc;
            const operation = decode(packet("p10"));
            if (operation === 0n) {
                write("20", pc + 4n);
                if (packet("D") !== "OK") throw new Error("Could not detach the debugger.");
                attached = false;
                pendingPC = null;
                return;
            }
            if (operation !== 1n) throw new Error("Unsupported JIT request.");
            let address = decode(packet("p0"));
            const length = decode(packet("p1"));
            if (!length || length % page || address % page) throw new Error("Invalid executable region.");
            const incremental = !address && decode(packet("p2")) === incrementalPreparation;
            if (!address) {
                const allocation = packet("_M" + hex(length) + ",rx");
                if (!/^[0-9a-f]+$/i.test(allocation)) throw new Error("Executable allocation failed.");
                address = BigInt("0x" + allocation);
            }
            if (address > BigInt(Number.MAX_SAFE_INTEGER) || length > BigInt(Number.MAX_SAFE_INTEGER)) {
                throw new Error("Executable region exceeds the debugger bridge's numeric range.");
            }
            if (incremental) {
                write("1", incrementalPreparation);
            } else {
                const prepared = prepare_memory_region(Number(address), Number(length));
                if (prepared !== "OK") throw new Error("Executable region preparation failed.");
            }
            write("0", address);
            write("20", pc + 4n);
            pendingPC = null;
            stopped = packet("c");
        }
    } finally {
        if (attached) {
            if (pendingPC !== null) {
                send_command("P0=" + encode(0n));
                send_command("P20=" + encode(pendingPC + 4n));
            }
            send_command("D");
        }
    }
}());
