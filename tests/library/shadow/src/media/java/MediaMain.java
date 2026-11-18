public final class MediaMain {
    public static void main(String[] args) {
        System.out.println("APPLICATION_PID=" + ProcessHandle.current().pid());
        MediaVideoProbe.main(args);
    }
}
