package room;

import javafx.application.Application;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Objects;

public final class Main {
    public static void main(String[] args) throws Exception {
        var session = Files.createTempDirectory("vfx-room-");
        session.toFile().deleteOnExit();
        for (String name : new String[]{"scenes.pck", "override.cfg", "result.txt"}) {
            session.resolve(name).toFile().deleteOnExit();
        }
        var pack = session.resolve("scenes.pck");
        try (var input = Objects.requireNonNull(Main.class.getResourceAsStream("scenes.pck"))) {
            Files.copy(input, pack);
        }
        boolean smoke = Arrays.asList(args).contains("--smoke");
        if (smoke) {
            String path = session.toString().replace('\\', '/').replace("\"", "\\\"");
            String config = "[room]\nsession=\"" + path + "\"\n[autoload]\nRoomSmoke=\"*res://smoke.gd\"\n";
            Files.writeString(session.resolve("override.cfg"), config);
        }
        System.setProperty("javafx.godot.project", pack.toString());
        Application.launch(WallControls.class, args);
        if (smoke) {
            String result = Files.readString(session.resolve("result.txt")).strip();
            if (!result.equals("PASS")) throw new AssertionError(result);
            System.out.println("ROOM_SMOKE_PASS");
        }
    }
}
