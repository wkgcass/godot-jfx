#include "frame_protocol.h"
#include "native_window_transport.h"
#include <iostream>
#include <stdexcept>
#include <thread>

using namespace godot_javafx;

static void require(bool condition, const char *message) {
	if (!condition) throw std::runtime_error(message);
}

static void put(std::vector<uint8_t> &bytes, uint32_t value) {
	for (int i = 0; i < 4; ++i) bytes.push_back(uint8_t(value >> (i * 8)));
}

static void replace(std::vector<uint8_t> &bytes, size_t offset, uint32_t value) {
	for (int i = 0; i < 4; ++i) bytes[offset + i] = uint8_t(value >> (i * 8));
}

static std::vector<uint8_t> valid_frame() {
	std::vector<uint8_t> bytes;
	for (uint32_t word : { FRAME_MAGIC, 1u, 48u, 2u, 1u, 0u,
			3u, 8u, 320u, 200u, 1u, 0u }) put(bytes, word);
	return bytes;
}

int main() {
	try {
		{
			std::vector<uint8_t> bytes;
			for(uint32_t word:{FRAME_MAGIC,1u,84u,2u,1u,0u,
				9u,16u,1u,1u,2u,2u,27u,28u,1u,1u,0u,0u,2u,2u})put(bytes,word);
			bytes.insert(bytes.end(),{0,85,170,255});
			Frame decoded;std::string error;
			require(decode_frame(bytes,decoded,error),"Compact alpha plane rejected");
			require(decoded.commands[1].pixels==std::vector<uint8_t>({0,85,170,255}),"Compact plane bytes changed");
			FrameQueue valid;
			require(valid.submit(std::move(decoded))==SubmitResult::ACCEPTED,"Compact alpha upload rejected");
			auto invalid=bytes;replace(invalid,48,10);
			require(!decode_frame(invalid,decoded,error),"RGBA opcode accepted single-channel payload");
			for(uint32_t allocation:{15u,18u}){
				invalid=bytes;replace(invalid,24,allocation);
				require(decode_frame(invalid,decoded,error),"Compact type test did not decode");
				FrameQueue wrong_type;
				require(wrong_type.submit(std::move(decoded))==SubmitResult::INVALID_RESOURCE,"Compact patch accepted target/float texture");
			}
			invalid=bytes;replace(invalid,64,2);
			require(decode_frame(invalid,decoded,error),"Out-of-bounds compact patch did not decode");
			FrameQueue atomic;
			require(atomic.submit(std::move(decoded))==SubmitResult::INVALID_RESOURCE,"Out-of-bounds compact patch accepted");
			require(decode_frame(bytes,decoded,error),"Compact atomic retry did not decode");
			require(atomic.submit(std::move(decoded))==SubmitResult::ACCEPTED,"Rejected compact patch changed queue resources/sequence");
			auto plane=bytes;replace(plane,24,28);
			require(decode_frame(plane,decoded,error),"R8 video allocation did not decode");
			FrameQueue video;
			require(video.submit(std::move(decoded))==SubmitResult::ACCEPTED,"R8 video plane patch rejected");
			plane.resize(96);replace(plane,8,96);replace(plane,48,10);replace(plane,52,40);
			require(decode_frame(plane,decoded,error),"RGBA-to-R8 type test did not decode");
			FrameQueue wrong_plane_format;
			require(wrong_plane_format.submit(std::move(decoded))==SubmitResult::INVALID_RESOURCE,"RGBA patch accepted R8 video plane");
		}
		{
			std::vector<uint8_t> bytes;
			for (uint32_t word : {FRAME_MAGIC, 1u, 72u, 4u, 1u, 0u,
				16u, 8u, 0u, 0u, 17u, 0u, 16u, 8u, 0u, 0u, 17u, 0u}) put(bytes, word);
			Frame decoded; std::string error;
			require(decode_frame(bytes, decoded, error), "Multiple ordered offscreen passes cannot share a transfer");
			FrameQueue queue;
			require(queue.submit(std::move(decoded)) == SubmitResult::ACCEPTED, "Batched offscreen transitions rejected");
			// A window presentation still ends the transfer; only END_PASS can
			// be followed by another target's commands.
			replace(bytes, 40, uint32_t(Opcode::PRESENT));
			require(!decode_frame(bytes, decoded, error), "Commands after presentation boundary accepted");
		}
		NativeWindowTransport window_queue;
		NativeWindowCommand create; create.operation=1; create.id=10; create.width=320; create.height=180;
		require(window_queue.submit(create)==1,"Native create sequence differs");
		bool rejected=false;
		try { window_queue.submit(create); } catch (const std::invalid_argument &) { rejected=true; }
		require(rejected,"Duplicate native identity accepted");
		create.id=11; create.owner=999; rejected=false;
		try { window_queue.submit(create); } catch (const std::invalid_argument &) { rejected=true; }
		require(rejected,"Unknown native owner accepted");
		create.owner=10; require(window_queue.submit(create)==2,"Rejected create consumed sequence");
		NativeWindowCommand destroy; destroy.operation=3; destroy.id=10;
		require(window_queue.submit(destroy)==3,"Owner destruction rejected");
		destroy.id=11; rejected=false;
		try { window_queue.submit(destroy); } catch (const std::invalid_argument &) { rejected=true; }
		require(rejected,"Destroyed child remained admitted");
		window_queue.finish();
		NativeWindowCommand native_taken;
		for(int64_t seq=1;seq<=3;++seq) require(window_queue.take(native_taken)&&native_taken.sequence==seq,"Native finish lost FIFO command");
		require(!window_queue.take(native_taken),"Native finish duplicated command");
		rejected=false;
		try { window_queue.submit(create); } catch (const NativeWindowTransportStopped &) { rejected=true; }
		require(rejected,"Native finish admitted work");
		{
			NativeWindowTransport cancelled;
			create.id=1; create.owner=0; cancelled.submit(create);
			cancelled.stop();
			require(!cancelled.take(native_taken),"Native stop retained pending command");
			rejected=false;
			try { cancelled.submit(create); } catch (const NativeWindowTransportStopped &) { rejected=true; }
			require(rejected,"Native stop did not report cancellation");
		}
		window_queue.publish({},3); require(window_queue.ack()==3&&window_queue.info(10).empty(),"Native snapshot acknowledgement differs");
		{
			NativeWindowTransport properties;
			create.id=1; create.owner=0; properties.submit(create);
			create.id=2; create.owner=-1;
			require(properties.submit(create)==2,"Root-owned native window rejected");
			NativeWindowCommand property; property.operation=4; property.id=1;
			for (int invalid_property : {0,2,3,5,8,10,11,14,99}) {
				property.flags=invalid_property; rejected=false;
				try { properties.submit(property); } catch (const std::invalid_argument &) { rejected=true; }
				require(rejected,"Unsupported native property admitted");
			}
			property.flags=6; property.x=5; rejected=false;
			try { properties.submit(property); } catch (const std::invalid_argument &) { rejected=true; }
			require(rejected,"Invalid native mode admitted");
			for (int boolean_property : {16,19,20}) {
				property.flags=boolean_property; property.x=2; rejected=false;
				try { properties.submit(property); } catch (const std::invalid_argument &) { rejected=true; }
				require(rejected,"Invalid native enabled/focusable value admitted");
			}
			property.flags=1; property.title=u"Independent title";
			for (int ime_property : {17,18}) {
				property.flags=ime_property; property.x=1000001; rejected=false;
				try { properties.submit(property); } catch (const std::invalid_argument &) { rejected=true; }
				require(rejected,"Invalid IME property payload admitted");
			}
			property.flags=1;
			require(properties.submit(property)==3,"Rejected property consumed sequence");
			require(properties.take(native_taken)&&properties.take(native_taken)&&properties.take(native_taken)&&native_taken.title==property.title,"Native property FIFO lost title");
			property.flags=22; property.x=0; property.y=0;
			require(properties.submit(property)==4,"Native lowering property rejected");
			require(properties.take(native_taken)&&native_taken.flags==22,"Native lowering property lost");
			property.x=1; rejected=false;
			try { properties.submit(property); } catch (const std::invalid_argument &) { rejected=true; }
			require(rejected,"Invalid native lowering payload admitted");
			property.flags=23; property.x=0;
			require(properties.submit(property)==5,"Native raising property rejected");
			require(properties.take(native_taken)&&native_taken.flags==23,"Native raising property lost");
			property.y=1; rejected=false;
			try { properties.submit(property); } catch (const std::invalid_argument &) { rejected=true; }
			require(rejected,"Invalid native raising payload admitted");
		}
		{
			NativeWindowTransport icons;
			NativeWindowCommand create_icon_window; create_icon_window.operation=1; create_icon_window.id=1; create_icon_window.width=32; create_icon_window.height=32;
			icons.submit(create_icon_window);
			NativeWindowCommand icon; icon.operation=5; icon.id=1; icon.width=256; icon.height=256; icon.icon_pixels.resize(256*256*4,255);
			for (int i=0;i<4;++i) require(icons.submit(icon)==i+2,"Icon sequence differs");
			rejected=false; try { icons.submit(icon); } catch(const std::runtime_error &) { rejected=true; }
			require(rejected,"Unbounded native icon bytes admitted");
			NativeWindowCommand taken; require(icons.take(taken)&&taken.operation==1,"Icon overtook window creation");
			for (int i=0;i<4;++i) require(icons.take(taken)&&taken.icon_pixels==icon.icon_pixels,"Icon payload lost in queue");
			icon.icon_pixels.pop_back(); rejected=false;
			try { icons.submit(icon); } catch(const std::invalid_argument &) { rejected=true; }
			require(rejected,"Malformed icon pixels admitted");
			icon.width=0; icon.height=0; icon.icon_pixels.clear();
			require(icons.submit(icon)==6,"Clear icon rejected or failed command consumed sequence");
			NativeWindowCommand close; close.id=1; close.operation=3; icons.submit(close);
			rejected=false; try { icons.submit(icon); } catch(const std::invalid_argument &) { rejected=true; }
			require(rejected,"Icon admitted after window close");
		}
		{
			std::vector<uint8_t> bytes;
			for (uint32_t word : {FRAME_MAGIC,1u,64u,1u,1u,0u,23u,32u,7u,0u,0u,0u,0x42800000u,0x42800000u,0xffffffffu,0x3f000000u}) put(bytes, word);
			Frame decoded; std::string error;
			require(decode_frame(bytes, decoded, error) && decoded.commands[0].window_z == -1 && decoded.commands[0].values[4] == .5f, "Window presentation decode failed");
			auto native_bytes=bytes; replace(native_bytes,24,26); Frame native_decoded;
			require(decode_frame(native_bytes,native_decoded,error)&&native_decoded.commands[0].opcode==Opcode::NATIVE_WINDOW_PRESENT,"Native publication decode failed");
			for (auto mutation : {std::pair<size_t,uint32_t>{32,0},{36,0x80000000u},{40,0x7fc00000u},{48,0},{52,0x46000100u},{60,0x3f800001u}}) {
				auto invalid = bytes; replace(invalid, mutation.first, mutation.second);
				require(!decode_frame(invalid, decoded, error), "Invalid window presentation accepted");
			}
			auto nonterminal = bytes; put(nonterminal, 1); put(nonterminal, 0);
			replace(nonterminal, 8, 72); replace(nonterminal, 12, 2);
			require(!decode_frame(nonterminal, decoded, error), "Drawing after window publication accepted");
			std::vector<uint8_t> removal;
			for (uint32_t word : {FRAME_MAGIC,1u,40u,1u,2u,0u,24u,8u,7u,0u}) put(removal, word);
			Frame removed;
			require(decode_frame(removal, removed, error) && removed.commands[0].window_id == 7, "Window removal decode failed");
			put(removal, 1); put(removal, 0); replace(removal, 8, 48); replace(removal, 12, 2);
			require(!decode_frame(removal, removed, error), "Nonterminal window removal accepted");
			auto configuration = bytes;
			replace(configuration, 8, 68); replace(configuration, 24, 25); replace(configuration, 28, 36); put(configuration, 0);
			Frame configured;
			require(decode_frame(configuration, configured, error) && !configured.commands[0].window_visible, "Window hide configuration decode failed");
			replace(configuration, 64, 2);
			require(!decode_frame(configuration, configured, error), "Invalid window visibility accepted");
			Command allocate; allocate.opcode = Opcode::TARGET_ALLOCATE; allocate.texture_handle = 0x100000001; allocate.width = allocate.height = 64;
			Command begin; begin.opcode = Opcode::BEGIN_PRESENT;
			Command select; select.opcode = Opcode::TARGET_SELECT; select.texture_handle = allocate.texture_handle;
			Command publish = decoded.commands[0];
			TextureLedger native_ledger; Frame native_frame;
			native_frame.commands={allocate,begin,select,native_decoded.commands[0]};
			require(native_ledger.apply(native_frame),"Native target publication rejected");
			Command native_dispose; native_dispose.opcode=Opcode::TEXTURE_DISPOSE; native_dispose.texture_handle=allocate.texture_handle;
			native_frame.commands={native_dispose}; require(!native_ledger.apply(native_frame),"Native published target disposed while retained");
			Command dispose; dispose.opcode = Opcode::TEXTURE_DISPOSE; dispose.texture_handle = allocate.texture_handle;
			Command remove; remove.opcode = Opcode::WINDOW_REMOVE; remove.window_id = 7;
			FrameQueue queue; uint64_t sequence = 0;
			auto submit = [&](std::initializer_list<Command> commands) {
				Frame f; f.sequence = ++sequence; f.commands = commands;
				auto result = queue.submit(std::move(f)); Frame consumed;
				if (result == SubmitResult::ACCEPTED) require(queue.take(consumed), "Accepted window batch missing");
				return result;
			};
			require(submit({allocate,begin,publish}) == SubmitResult::INVALID_RESOURCE, "Window accepted without GPU target");
			require(submit({allocate,begin,select,publish}) == SubmitResult::ACCEPTED, "Window target publication failed");
			require(submit({configured.commands[0]}) == SubmitResult::ACCEPTED, "Published window state update failed");
			require(submit({begin,configured.commands[0]}) == SubmitResult::INVALID_RESOURCE, "State update split an open presentation");
			require(submit({select,configured.commands[0]}) == SubmitResult::INVALID_RESOURCE, "State update split an empty target pass");
			require(submit({select,remove}) == SubmitResult::INVALID_RESOURCE, "Window removal split an empty target pass");
			require(submit({dispose}) == SubmitResult::INVALID_RESOURCE, "Published target disposal escaped resource budget");
			for (uint64_t id = 8; id < 71; ++id) {
				publish.window_id = id;
				require(submit({begin,select,publish}) == SubmitResult::ACCEPTED, "Valid retained window rejected");
			}
			publish.window_id = 71;
			require(submit({begin,select,publish}) == SubmitResult::INVALID_RESOURCE, "Window layer limit not enforced");
			require(submit({remove}) == SubmitResult::ACCEPTED, "Window removal failed");
			require(submit({configured.commands[0]}) == SubmitResult::INVALID_RESOURCE, "Configuration resurrected a removed window");
			require(submit({dispose}) == SubmitResult::INVALID_RESOURCE, "Shared retained target released too early");
			for (uint64_t id = 8; id < 71; ++id) { remove.window_id = id; require(submit({remove}) == SubmitResult::ACCEPTED, "Layer cleanup failed"); }
			require(submit({dispose}) == SubmitResult::ACCEPTED, "Removed window still pins target");
		}
		{
			std::vector<uint8_t> bytes;
			for (uint32_t word : {FRAME_MAGIC,1u,72u,1u,2u,0u,22u,40u,1u,1u,1u,1u,1u,0u,0x41a00000u,0x41a00000u,0u,0u}) put(bytes,word);
			Frame input; std::string error;
			require(decode_frame(bytes,input,error) && input.commands[0].values[0] == 20,"Scene input decode failed");
			for (auto value : {std::pair<size_t,uint32_t>{40,6},{44,64},{48,10},{52,0xd800},{56,0x7fc00000}}) {
				auto invalid = bytes; replace(invalid,value.first,value.second);
				require(!decode_frame(invalid,input,error),"Malformed scene input accepted");
			}
			Command allocation; allocation.opcode = Opcode::SCENE_TEXTURE_ALLOCATE; allocation.texture_handle = 0x100000001; allocation.width = allocation.height = 64;
			Frame initial; initial.sequence = 1; initial.commands = {allocation};
			FrameQueue queue;
			require(queue.submit(Frame(initial)) == SubmitResult::ACCEPTED && queue.submit(Frame(input)) == SubmitResult::ACCEPTED,"Valid scene input rejected");
			allocation.opcode = Opcode::TEXTURE_ALLOCATE; initial.commands = {allocation}; FrameQueue image_queue;
			require(image_queue.submit(std::move(initial)) == SubmitResult::ACCEPTED && image_queue.submit(Frame(input)) == SubmitResult::INVALID_RESOURCE,"Input accepted for ordinary image texture");
			Command dispose; dispose.opcode = Opcode::TEXTURE_DISPOSE; dispose.texture_handle = allocation.texture_handle;
			Frame release; release.sequence = 3; release.commands = {dispose};
			require(queue.submit(std::move(release)) == SubmitResult::ACCEPTED,"Scene input disposal failed");
			Frame taken; queue.take(taken); input.sequence = 4;
			require(queue.submit(std::move(input)) == SubmitResult::INVALID_RESOURCE,"Input accepted for disposed scene");
		}
		{
			Command allocation; allocation.opcode = Opcode::SCENE_TEXTURE_ALLOCATE; allocation.texture_handle = 0x100000001; allocation.width = allocation.height = 64;
			Command sample; sample.opcode = Opcode::TEXTURED_QUADS; sample.texture_handle = allocation.texture_handle;
			Command resize; resize.opcode = Opcode::SCENE_TEXTURE_RESIZE; resize.texture_handle = 0x100000002; resize.source_handle = allocation.texture_handle; resize.width = 96; resize.height = 64;
			FrameQueue queue; Frame initial; initial.sequence = 1; initial.commands = {allocation,sample};
			require(queue.submit(std::move(initial)) == SubmitResult::ACCEPTED,"Scene resize setup rejected");
			Frame unsafe; unsafe.sequence = 2; unsafe.commands = {resize};
			require(queue.submit(std::move(unsafe)) == SubmitResult::INVALID_RESOURCE,"Resize accepted before sampled scene pass completed");
			Command end; end.opcode = Opcode::END_PASS; Frame boundary; boundary.sequence = 2; boundary.commands = {end};
			require(queue.submit(std::move(boundary)) == SubmitResult::ACCEPTED,"Scene pass completion rejected");
			Frame safe; safe.sequence = 3; safe.commands = {resize};
			require(queue.submit(std::move(safe)) == SubmitResult::ACCEPTED,"Scene resize rejected after pass completion");
			Frame taken; queue.take(taken);
			Command dispose; dispose.opcode = Opcode::TEXTURE_DISPOSE; dispose.texture_handle = allocation.texture_handle;
			Frame stale; stale.sequence = 4; stale.commands = {dispose};
			require(queue.submit(std::move(stale)) == SubmitResult::INVALID_RESOURCE,"Consumed scene handle remained live after resize");
			std::vector<uint8_t> bytes;
			for (uint32_t word : {FRAME_MAGIC,1u,56u,1u,1u,0u,21u,24u,2u,1u,1u,1u,96u,64u}) put(bytes,word);
			std::string error;
			require(decode_frame(bytes,taken,error) && taken.commands[0].source_handle == allocation.texture_handle,"Scene resize decode failed");
			replace(bytes,48,0);
			require(!decode_frame(bytes,taken,error),"Zero scene resize dimension accepted");
		}
		{
			std::string path = "res://embedded_scene.tscn";
			std::vector<uint8_t> bytes;
			for (uint32_t word : {FRAME_MAGIC,1u,uint32_t(52+path.size()),1u,1u,0u,20u,uint32_t(20+path.size()),1u,1u,96u,64u,uint32_t(path.size())}) put(bytes,word);
			bytes.insert(bytes.end(),path.begin(),path.end());
			Frame frame; std::string error;
			require(decode_frame(bytes,frame,error) && frame.commands[0].scene_path == path,"Scene texture decode failed");
			auto invalid = bytes; invalid[52] = 'x';
			require(!decode_frame(invalid,frame,error),"Non-resource scene path accepted");
			invalid = bytes; invalid.back() = 0;
			require(!decode_frame(invalid,frame,error),"NUL scene path accepted");
			invalid = bytes; replace(invalid,48,4097);
			require(!decode_frame(invalid,frame,error),"Oversized scene path accepted");
			FrameQueue queue;
			require(queue.submit(Frame(frame)) == SubmitResult::ACCEPTED,"Scene allocation rejected");
			Command patch; patch.opcode = Opcode::TEXTURE_PATCH; patch.texture_handle = 0x100000001; patch.width = patch.height = 1;
			Frame write; write.sequence = 2; write.commands = {patch};
			require(queue.submit(std::move(write)) == SubmitResult::INVALID_RESOURCE,"CPU upload accepted on scene texture");
			patch.opcode = Opcode::TARGET_SELECT; Frame target; target.sequence = 2; target.commands = {patch};
			require(queue.submit(std::move(target)) == SubmitResult::INVALID_RESOURCE,"Scene texture accepted as Prism drawing target");
			patch.opcode = Opcode::TEXTURED_QUADS; Frame sample; sample.sequence = 2; sample.commands = {patch};
			require(queue.submit(std::move(sample)) == SubmitResult::ACCEPTED,"Scene sampling rejected after transaction rollback");
			patch.opcode = Opcode::TEXTURE_DISPOSE; Frame dispose; dispose.sequence = 3; dispose.commands = {patch};
			require(queue.submit(std::move(dispose)) == SubmitResult::ACCEPTED,"Referenced scene disposal rejected");
		}
		{
			std::vector<uint8_t> bytes;
			for (uint32_t word : {FRAME_MAGIC,1u,72u,1u,1u,0u,19u,40u,1u,1u,0u,0u,1u,1u,0xbf800000u,0x40000000u,0u,0x3f800000u}) put(bytes,word);
			Frame frame; std::string error;
			require(decode_frame(bytes,frame,error) && frame.commands[0].pixels.size() == 16, "Signed float texture decode failed");
			auto invalid = bytes; replace(invalid,56,0x7fc00000);
			require(!decode_frame(invalid,frame,error), "NaN float texture accepted");
			invalid = bytes; replace(invalid,56,0x7f800000);
			require(!decode_frame(invalid,frame,error), "Infinite float texture accepted");
			invalid = bytes; replace(invalid,24,10);
			require(!decode_frame(invalid,frame,error), "Float bytes accepted as RGBA8 patch");
			Command allocation; allocation.opcode = Opcode::FLOAT_TEXTURE_ALLOCATE; allocation.texture_handle = 0x100000001; allocation.width = allocation.height = 4096;
			Frame setup; setup.sequence = 1; setup.commands = {allocation};
			FrameQueue queue;
			require(queue.submit(std::move(setup)) == SubmitResult::ACCEPTED, "Float allocation rejected");
			Command patch = frame.commands[0]; patch.opcode = Opcode::TEXTURE_PATCH;
			Frame mismatch; mismatch.sequence = 2; mismatch.commands = {patch};
			require(queue.submit(std::move(mismatch)) == SubmitResult::INVALID_RESOURCE, "RGBA8 patch accepted on float texture");
			Frame valid = frame; valid.sequence = 2;
			require(queue.submit(std::move(valid)) == SubmitResult::ACCEPTED, "Float patch rejected after mismatch rollback");
			// The budget rule itself: a float allocation one pixel over the
			// ledger ceiling must be rejected regardless of the constant's
			// current value (it is coordinated with the Java-side pool).
			uint64_t over = godot_javafx::TextureLedger::MAX_BYTES / 16 + 1;
			allocation.texture_handle = 0x100000002;
			allocation.width = int(over / 2 + 1); allocation.height = 2;
			Frame excess; excess.sequence = 3; excess.commands = {allocation};
			require(queue.submit(std::move(excess)) == SubmitResult::INVALID_RESOURCE, "Float texture budget ceiling not enforced");
		}
		{
			FrameQueue queue;
			auto boundary = [&](uint64_t sequence, std::initializer_list<Opcode> operations) {
				Frame frame; frame.sequence = sequence;
				for (Opcode op : operations) { Command command; command.opcode = op; frame.commands.push_back(command); }
				return queue.submit(std::move(frame));
			};
			require(boundary(1, {Opcode::PRESENT}) == SubmitResult::INVALID_RESOURCE, "Present without begin accepted");
			require(boundary(1, {Opcode::BEGIN_PRESENT, Opcode::BEGIN_PRESENT}) == SubmitResult::INVALID_RESOURCE, "Nested present accepted");
			require(boundary(1, {Opcode::BEGIN_PRESENT}) == SubmitResult::ACCEPTED, "Begin rejected after rollback");
			require(boundary(2, {Opcode::QUADS, Opcode::PRESENT}) == SubmitResult::ACCEPTED, "Split frame rejected");
			require(boundary(3, {Opcode::QUADS}) == SubmitResult::INVALID_RESOURCE, "Draw outside presentation accepted");
			require(boundary(3, {Opcode::BEGIN_PRESENT, Opcode::CLEAR, Opcode::PRESENT}) == SubmitResult::ACCEPTED, "Next presentation rejected");
		}
		{
			// Geometry deduplication handshake: register once, redraw by
			// reference, retire exactly once, never re-register live handles.
			FrameQueue queue;
			auto submit_commands = [&](uint64_t sequence, std::initializer_list<Command> commands) {
				Frame frame; frame.sequence = sequence;
				for (const Command &command : commands) frame.commands.push_back(command);
				SubmitResult result = queue.submit(std::move(frame));
				Frame drain;
				while (queue.take(drain)) {} // Keep room; projection state is what matters here.
				return result;
			};
			Command begin; begin.opcode = Opcode::BEGIN_PRESENT;
			Command tagged; tagged.opcode = Opcode::QUADS; tagged.geometry_handle = 7;
			Command reference; reference.opcode = Opcode::QUADS_REF; reference.geometry_handle = 7;
			Command foreign; foreign.opcode = Opcode::QUADS_REF; foreign.geometry_handle = 99;
			Command retire; retire.opcode = Opcode::GEOMETRY_FREE; retire.geometry_handle = 7;
			Command untagged; untagged.opcode = Opcode::QUADS;
			require(submit_commands(1, {begin, tagged}) == SubmitResult::ACCEPTED, "Tagged quad registration rejected");
			require(submit_commands(2, {reference}) == SubmitResult::ACCEPTED, "Geometry reference rejected");
			require(submit_commands(3, {foreign}) == SubmitResult::INVALID_RESOURCE, "Unknown geometry reference accepted");
			require(submit_commands(3, {tagged}) == SubmitResult::INVALID_RESOURCE, "Live handle re-registration accepted");
			require(submit_commands(3, {retire}) == SubmitResult::ACCEPTED, "Geometry retirement rejected");
			require(submit_commands(4, {reference}) == SubmitResult::INVALID_RESOURCE, "Retired geometry still referenceable");
			require(submit_commands(4, {retire}) == SubmitResult::INVALID_RESOURCE, "Double retirement accepted");
			require(submit_commands(4, {untagged}) == SubmitResult::ACCEPTED, "Untagged quad rejected");
		}
		{
			// A late geometry failure must roll back texture allocation, geometry
			// retirement and sequence admission together, not just the failing entry.
			FrameQueue queue;
			auto submit = [&](uint64_t sequence, std::initializer_list<Command> commands) {
				Frame frame; frame.sequence = sequence; frame.commands = commands;
				return queue.submit(std::move(frame));
			};
			Command texture; texture.opcode = Opcode::TEXTURE_ALLOCATE;
			texture.texture_handle = (uint64_t(1) << 32) | 1;
			texture.width = texture.height = 8;
			Command tagged; tagged.opcode = Opcode::QUADS; tagged.geometry_handle = 7;
			Command unknown; unknown.opcode = Opcode::QUADS_REF; unknown.geometry_handle = 99;
			Command reference = unknown; reference.geometry_handle = 7;
			Command retire; retire.opcode = Opcode::GEOMETRY_FREE; retire.geometry_handle = 7;
			Frame drained;
			require(submit(1, {texture, tagged, unknown}) == SubmitResult::INVALID_RESOURCE, "Partial resource transaction accepted");
			require(queue.get_last_sequence() == 0 && !queue.take(drained), "Rejected transaction entered queue or consumed sequence");
			require(submit(1, {texture, tagged}) == SubmitResult::ACCEPTED, "Rejected transaction leaked texture or geometry registration");
			require(queue.take(drained) && drained.sequence == 1, "Retried transaction missing");
			require(submit(2, {retire, unknown}) == SubmitResult::INVALID_RESOURCE, "Invalid retirement transaction accepted");
			require(queue.get_last_sequence() == 1 && !queue.take(drained), "Rejected retirement consumed sequence or queued work");
			reference.texture_handle = texture.texture_handle;
			require(submit(2, {reference}) == SubmitResult::ACCEPTED, "Rejected retirement invalidated live geometry or texture");
			require(queue.take(drained) && drained.sequence == 2, "Reference retry missing");
			std::cout << "FRAME_RESOURCE_TRANSACTION_PASS\n";
		}
		{
			// Wire format: QUADS carries its handle; QUADS_REF and
			// GEOMETRY_FREE decode their fixed payloads.
			std::vector<uint8_t> bytes;
			for (uint32_t word : {FRAME_MAGIC, 1u, 0u, 3u, 1u, 0u}) put(bytes, word);
			put(bytes, 4u); put(bytes, 4u * 32 + 40u); put(bytes, 7u); put(bytes, 0u); put(bytes, 4u);
			for (int v = 0; v < 4; ++v) for (int a = 0; a < 8; ++a) put(bytes, a == 7 ? 0x00ff00ffu : (a < 7 && a != 2 ? 0x3f000000u : 0u));
			for (uint32_t t = 0; t < 6; ++t) put(bytes, 0x3f800000u);
			put(bytes, 0x3f000000u);
			put(bytes, 29u); put(bytes, 44u); put(bytes, 7u); put(bytes, 0u); put(bytes, 0u); put(bytes, 0u);
			for (uint32_t t = 0; t < 6; ++t) put(bytes, 0x3f800000u);
			put(bytes, 0x3f000000u);
			put(bytes, 30u); put(bytes, 8u); put(bytes, 7u); put(bytes, 0u);
			uint32_t length = uint32_t(bytes.size());
			bytes[8] = length & 0xff; bytes[9] = (length >> 8) & 0xff; bytes[10] = (length >> 16) & 0xff; bytes[11] = (length >> 24) & 0xff;
			Frame decoded; std::string error;
			require(decode_frame(bytes, decoded, error), "Geometry wire frame rejected");
			require(decoded.commands.size() == 3, "Geometry wire frame command count differs");
			require(decoded.commands[0].geometry_handle == 7, "QUADS handle not decoded");
			require(decoded.commands[0].draw_alpha == 0.5f, "QUADS draw modulation not decoded");
			require(decoded.commands[1].opcode == Opcode::QUADS_REF && decoded.commands[1].geometry_handle == 7 && decoded.commands[1].draw_alpha == 0.5f, "QUADS_REF not decoded");
			require(decoded.commands[2].opcode == Opcode::GEOMETRY_FREE && decoded.commands[2].geometry_handle == 7, "GEOMETRY_FREE not decoded");
			auto bad = bytes;
			// Zero the QUADS_REF handle (payload starts at 24 + 176 + 8).
			for (int b = 0; b < 4; ++b) bad[208 + b] = 0;
			require(!decode_frame(bad, decoded, error), "Zero geometry reference handle accepted");
			bad = bytes;
			// Modulation beyond 1.0 in the QUADS_REF tail (alpha at 248).
			replace(bad, 248, 0x40000000u);
			require(!decode_frame(bad, decoded, error), "Out-of-range reference modulation accepted");
		}
		{
			std::vector<uint8_t> bytes;
			for (uint32_t word : {FRAME_MAGIC, 1u, 52u, 1u, 1u, 0u, 12u, 20u, 1u, 0xfffffff6u, 10u, 20u, 0u}) put(bytes, word);
			Frame decoded; std::string error;
			require(decode_frame(bytes, decoded, error), "Valid negative-origin/empty clip rejected");
			auto invalid = bytes; replace(invalid, 32, 2);
			require(!decode_frame(invalid, decoded, error), "Invalid clip enable flag accepted");
			invalid = bytes; replace(invalid, 44, 0xffffffff);
			require(!decode_frame(invalid, decoded, error), "Negative clip width accepted");
			invalid = bytes; replace(invalid, 32, 0);
			require(!decode_frame(invalid, decoded, error), "Noncanonical disabled clip accepted");
		}
		{
			std::vector<uint8_t> bytes;
			for (uint32_t word : { FRAME_MAGIC, 1u, 0u, 1u, 1u, 0u, 11u, 0u }) put(bytes, word);
			std::string source = "shader_type canvas_item; uniform float gain;";
			put(bytes, uint32_t(source.size())); bytes.insert(bytes.end(), source.begin(), source.end());
			put(bytes, 1); put(bytes, 4); bytes.insert(bytes.end(), {'g', 'a', 'i', 'n'});
			size_t shape = bytes.size();
			put(bytes, 0); put(bytes, 1); put(bytes, 0); put(bytes, 0x3f800000);
			put(bytes, 0); // sampler count
			replace(bytes, 8, uint32_t(bytes.size())); replace(bytes, 28, uint32_t(bytes.size() - 32));
			Frame decoded; std::string error;
			require(decode_frame(bytes, decoded, error), "Shader state decode rejected");
			require(decoded.commands[0].constants[0].words[0] == 0x3f800000, "Shader word changed");
			auto invalid = bytes; replace(invalid, shape + 12, 0x7f800000);
			require(!decode_frame(invalid, decoded, error), "Infinite shader value accepted");
			invalid = bytes; replace(invalid, shape + 8, 1025);
			require(!decode_frame(invalid, decoded, error), "Oversized shader array accepted");
			for (uint32_t components : { 0u, 5u, 0xffffffffu }) {
				invalid = bytes; replace(invalid, shape + 4, components);
				require(!decode_frame(invalid, decoded, error) && error == "Invalid shader constant shape",
						"Out-of-range component count reached shader word decoding");
			}
			invalid = bytes; replace(invalid, shape, 2);
			require(!decode_frame(invalid, decoded, error), "Unknown shader constant type accepted");
			invalid = bytes; invalid.resize(shape + 15); replace(invalid, 8, uint32_t(invalid.size())); replace(invalid, 28, uint32_t(invalid.size() - 32));
			require(!decode_frame(invalid, decoded, error), "Truncated shader constant accepted");
			invalid = bytes; replace(invalid, invalid.size() - 4, 17);
			require(!decode_frame(invalid, decoded, error), "Oversized sampler list accepted");
			require(decoded.commands[0].constants[0].words[0] == 0x3f800000, "Rejected shader decode changed output");
		}
		{
			auto resource = [](Opcode op, uint64_t handle, uint32_t size = 1) {
				Command command; command.opcode = op; command.texture_handle = handle;
				command.width = command.height = size;
				return command;
			};
			auto submit = [](FrameQueue &queue, uint64_t sequence, std::initializer_list<Command> commands) {
				Frame frame; frame.sequence = sequence; frame.commands = commands;
				return queue.submit(std::move(frame));
			};
			constexpr uint64_t first = (1ull << 32) | 1, other = (1ull << 32) | 2, reused = (2ull << 32) | 1;
			FrameQueue resources;
			FrameQueue rt_resources;
			require(submit(rt_resources, 1, { resource(Opcode::TARGET_ALLOCATE, first, 32) }) == SubmitResult::ACCEPTED, "RT allocation rejected");
			require(submit(rt_resources, 2, { resource(Opcode::TEXTURE_UPDATE, first, 32) }) == SubmitResult::INVALID_RESOURCE, "RT accepted CPU image upload");
			require(submit(rt_resources, 2, { resource(Opcode::TEXTURED_QUADS, first), resource(Opcode::TEXTURE_DISPOSE, first) }) == SubmitResult::ACCEPTED, "RT sample/disposal rejected");
			FrameQueue passes;
			require(submit(passes, 1, { resource(Opcode::TARGET_ALLOCATE, first, 32), resource(Opcode::TEXTURE_ALLOCATE, other, 32), resource(Opcode::TARGET_SELECT, first), resource(Opcode::QUADS, 0) }) == SubmitResult::ACCEPTED, "RT drawing pass rejected");
			require(submit(passes, 2, { resource(Opcode::TARGET_SELECT, other) }) == SubmitResult::INVALID_RESOURCE, "Image texture accepted as target");
			require(submit(passes, 2, { resource(Opcode::TEXTURED_QUADS, first) }) == SubmitResult::INVALID_RESOURCE, "Target feedback accepted");
			require(submit(passes, 2, { resource(Opcode::TARGET_SELECT, 0) }) == SubmitResult::INVALID_RESOURCE, "Target switch skipped an unfinished pass");
			require(submit(passes, 2, { resource(Opcode::END_PASS, 0) }) == SubmitResult::ACCEPTED, "Pass end rejected after rollback");
			require(submit(passes, 3, { resource(Opcode::TARGET_SELECT, 0), resource(Opcode::TEXTURED_QUADS, first) }) == SubmitResult::ACCEPTED, "Completed RT cannot be sampled");
			Command sampler; sampler.opcode = Opcode::SHADER_STATE; sampler.samplers["image"] = first;
			require(submit(resources, 1, { sampler }) == SubmitResult::INVALID_RESOURCE, "Unallocated shader sampler accepted");
			require(submit(resources, 1, { resource(Opcode::TEXTURE_CREATE, first) }) == SubmitResult::ACCEPTED, "Texture creation rejected");
			FrameQueue sampler_budget;
			// 16384^2 * 4B = the current ledger ceiling exactly; a sampler-
			// retained update must account both versions (2x ceiling).
			require(submit(sampler_budget, 1, { resource(Opcode::TEXTURE_ALLOCATE, first, 16384), sampler }) == SubmitResult::ACCEPTED, "Valid sampler rejected");
			require(submit(sampler_budget, 2, { resource(Opcode::TEXTURE_UPDATE, first, 16384) }) == SubmitResult::INVALID_RESOURCE, "Sampler did not retain texture budget");
			FrameQueue presented_budget;
			Command begin, present; begin.opcode = Opcode::BEGIN_PRESENT; present.opcode = Opcode::PRESENT;
			FrameQueue snapshots;
			require(submit(snapshots, 1, { begin, resource(Opcode::TARGET_ALLOCATE, first, 32), resource(Opcode::TARGET_SELECT, first), resource(Opcode::QUADS, 0), present }) == SubmitResult::ACCEPTED, "Snapshot setup presentation rejected");
			require(submit(snapshots, 2, { resource(Opcode::TARGET_SELECT, first), resource(Opcode::CLEAR, 0), resource(Opcode::QUADS, 0), resource(Opcode::END_PASS, 0) }) == SubmitResult::ACCEPTED, "Standalone offscreen pass after presentation rejected");
			require(submit(snapshots, 3, { resource(Opcode::TARGET_SELECT, 0), resource(Opcode::CLEAR, 0) }) == SubmitResult::INVALID_RESOURCE, "Root drawing outside presentation accepted");
			require(submit(snapshots, 3, { resource(Opcode::TARGET_SELECT, first), resource(Opcode::QUADS, 0), present }) == SubmitResult::INVALID_RESOURCE, "Publication without BEGIN_PRESENT accepted");
			require(submit(snapshots, 3, { begin, resource(Opcode::TARGET_SELECT, first), resource(Opcode::QUADS, 0), present }) == SubmitResult::ACCEPTED, "Presentation after standalone snapshot rejected");
			require(submit(presented_budget, 1, { begin, resource(Opcode::TEXTURE_ALLOCATE, first, 8192), sampler, present }) == SubmitResult::ACCEPTED, "Presented sampler rejected");
			require(submit(presented_budget, 2, { resource(Opcode::TEXTURE_UPDATE, first, 8192) }) == SubmitResult::ACCEPTED, "Presented texture version retained projected budget");
			require(submit(resources, 2, { resource(Opcode::TEXTURE_CREATE, other), resource(Opcode::TEXTURE_DISPOSE, reused) }) == SubmitResult::INVALID_RESOURCE, "Invalid transaction accepted");
			require(submit(resources, 2, { resource(Opcode::TEXTURE_CREATE, other) }) == SubmitResult::ACCEPTED, "Rejected transaction reserved a generation/sequence");
			require(submit(resources, 3, { resource(Opcode::TEXTURE_DISPOSE, first), resource(Opcode::TEXTURED_QUADS, first) }) == SubmitResult::INVALID_RESOURCE, "Use after dispose accepted");
			require(submit(resources, 3, { resource(Opcode::TEXTURED_QUADS, first) }) == SubmitResult::ACCEPTED, "Failed transaction invalidated live resource");
			Frame consumed;
			while (resources.take(consumed)) {}
			require(submit(resources, 4, { resource(Opcode::TEXTURE_DISPOSE, first), resource(Opcode::TEXTURE_CREATE, reused) }) == SubmitResult::ACCEPTED, "Generation reuse rejected");
			require(submit(resources, 5, { resource(Opcode::TEXTURED_QUADS, first) }) == SubmitResult::INVALID_RESOURCE, "Stale generation accepted");
			require(submit(resources, 5, { resource(Opcode::TEXTURE_UPDATE, reused, 2) }) == SubmitResult::INVALID_RESOURCE, "Texture dimension change accepted");
			require(submit(resources, 5, { resource(Opcode::TEXTURE_DISPOSE, reused), resource(Opcode::TEXTURE_CREATE, first) }) == SubmitResult::INVALID_RESOURCE, "Old generation recreated");
			require(submit(resources, 5, { resource(Opcode::TEXTURED_QUADS, reused) }) == SubmitResult::ACCEPTED, "Rollback lost new generation");
			Command patch = resource(Opcode::TEXTURE_PATCH, reused);
			patch.x = UINT32_MAX;
			require(submit(resources, 6, { patch }) == SubmitResult::INVALID_RESOURCE, "Overflowing region origin accepted");
			patch.x = 1;
			require(submit(resources, 6, { patch }) == SubmitResult::INVALID_RESOURCE, "Out-of-bounds region accepted");
			patch.x = 0;
			require(submit(resources, 6, { patch }) == SubmitResult::ACCEPTED, "Valid region rejected after rollback");
			FrameQueue budget;
			require(submit(budget, 1, { resource(Opcode::TEXTURE_ALLOCATE, first, 16384), resource(Opcode::TEXTURE_UPDATE, first, 16384),
				resource(Opcode::TEXTURE_UPDATE, first, 16384), resource(Opcode::TEXTURED_QUADS, first) }) == SubmitResult::ACCEPTED, "Unreferenced updates retired unnecessary versions");
			require(submit(budget, 2, { resource(Opcode::TEXTURE_UPDATE, first, 16384) }) == SubmitResult::INVALID_RESOURCE, "Retired versions bypassed memory limit");
			require(submit(budget, 2, { resource(Opcode::TEXTURE_DISPOSE, first), resource(Opcode::CLEAR, 0), resource(Opcode::TEXTURE_CREATE, reused, 8192) }) == SubmitResult::ACCEPTED, "Clear did not reclaim retired budget");
		}
		{
			std::vector<uint8_t> allocation;
			for (uint32_t word : { FRAME_MAGIC, 1u, 48u, 1u, 1u, 0u, 9u, 16u, 1u, 1u, 1024u, 1024u }) put(allocation, word);
			Frame result; std::string error;
			require(decode_frame(allocation, result, error) && result.commands[0].pixels.empty() && result.commands[0].width == 1024, "Large empty texture allocation failed decoding");
			std::vector<uint8_t> patch;
			for (uint32_t word : { FRAME_MAGIC, 1u, 60u, 1u, 1u, 0u, 10u, 28u, 1u, 1u, 1023u, 1023u, 1u, 1u, 0xffff0000u }) put(patch, word);
			require(decode_frame(patch, result, error) && result.commands[0].x == 1023 && result.commands[0].pixels.size() == 4, "Texture region payload changed");
			replace(patch, 48, 2);
			require(!decode_frame(patch, result, error), "Region pixel length mismatch accepted");
		}
		{
			std::vector<uint8_t> quads;
			for (uint32_t word : { FRAME_MAGIC, 1u, 200u, 1u, 1u, 0u, 4u, 168u, 0u, 0u, 4u }) put(quads, word);
			for (int vertex = 0; vertex < 4; ++vertex) {
				for (int component = 0; component < 7; ++component) put(quads, component == 2 ? 0u : 0x3f000000u);
				put(quads, 0xff00ff00u);
			}
			for (uint32_t word : { 0x3f800000u, 0u, 0u, 0u, 0x3f800000u, 0u }) put(quads, word);
			put(quads, 0x3f000000u);
			Frame result;
			std::string error;
			require(decode_frame(quads, result, error), "Valid quad frame rejected");
			require(result.commands[0].vertices.size() == 28 && result.commands[0].vertices[6] == 0.5f && result.commands[0].colors[1] == 255, "Quad attributes corrupted");
			require(result.commands[0].transform[0] == 1.0f && result.commands[0].transform[1] == 0.0f && result.commands[0].transform[4] == 1.0f, "Quad transform corrupted");
			require(result.commands[0].draw_alpha == 0.5f, "Quad draw modulation not decoded");
			for (auto invalid : { std::pair<size_t, uint32_t>{36, 0xffffffffu}, {40, 3}, {40, 65540}, {44, 0x7fc00000}, {52, 0x3f800000}, {172, 0x7fc00000}, {196, 0x7fc00000}, {196, 0x40000000u} }) {
				auto malformed = quads;
				replace(malformed, invalid.first, invalid.second);
				require(!decode_frame(malformed, result, error), "Invalid quad attributes accepted");
				require(result.commands[0].vertices.size() == 28, "Rejected quad changed output");
			}
		}
		auto bytes = valid_frame();
		Frame decoded;
		std::string error;
		require(decode_frame(bytes, decoded, error), "Valid frame rejected");
		require(decoded.sequence == 1 && decoded.commands.size() == 2, "Frame lost data");
		require(decoded.commands[0].width == 320 && decoded.commands[1].opcode == Opcode::CLEAR, "Payload changed");
		// Rejection must leave output untouched, including failures at the end.
		for (size_t offset : { size_t(0), size_t(4), size_t(8), size_t(12), size_t(24), size_t(28), size_t(32), size_t(40), size_t(44) }) {
			auto malformed = bytes;
			replace(malformed, offset, 0xffffffff);
			require(!decode_frame(malformed, decoded, error), "Malformed frame accepted");
			require(decoded.commands.size() == 2 && !error.empty(), "Rejection corrupted output");
		}
		for (size_t length = 0; length < bytes.size(); ++length) {
			auto truncated = bytes;
			truncated.resize(length);
			require(!decode_frame(truncated, decoded, error), "Truncation accepted");
		}
		FrameQueue queue;
		for (uint64_t i = 1; i <= 3; ++i) {
			Frame frame; frame.sequence = i;
			require(queue.submit(std::move(frame)) == SubmitResult::ACCEPTED, "Queue rejected available slot");
		}
		Frame retry; retry.sequence = 4;
		require(queue.submit(std::move(retry)) == SubmitResult::FULL, "Queue is unbounded");
		require(queue.take(decoded) && decoded.sequence == 1, "Queue reordered frames");
		require(queue.submit(std::move(retry)) == SubmitResult::ACCEPTED, "Backpressure retry consumed sequence");
		Frame stale; stale.sequence = 4;
		require(queue.submit(std::move(stale)) == SubmitResult::STALE, "Stale sequence accepted");
		queue.stop();
		require(!queue.take(decoded) && queue.await_tick(0, 1) == -1, "Stop retained queued work or waiter");
		Frame stopped; stopped.sequence = 5;
		require(queue.submit(std::move(stopped)) == SubmitResult::STOPPED, "Submit after stop accepted");

		FrameQueue concurrent;
		FrameQueue finishing;
		for (uint64_t i = 1; i <= 3; ++i) {
			Frame frame; frame.sequence = i;
			require(finishing.submit(std::move(frame)) == SubmitResult::ACCEPTED, "Finish setup rejected");
		}
		finishing.finish();
		require(finishing.await_tick(0, 1) == -1, "Finish did not wake waiter");
		Frame late; late.sequence = 4;
		require(finishing.submit(std::move(late)) == SubmitResult::STOPPED, "Finish admitted late work");
		for (uint64_t i = 1; i <= 3; ++i)
			require(finishing.take(decoded) && decoded.sequence == i, "Finish lost/reordered admitted work");
		require(!finishing.take(decoded), "Finish duplicated work");
		finishing.stop();
		constexpr uint64_t count = 10000;
		std::thread producer([&] {
			for (uint64_t i = 1; i <= count; ++i) {
				Frame frame; frame.sequence = i;
				while (concurrent.submit(std::move(frame)) == SubmitResult::FULL) std::this_thread::yield();
			}
		});
		bool ordered = true;
		for (uint64_t i = 1; i <= count; ++i) {
			while (!concurrent.take(decoded)) std::this_thread::yield();
			ordered = ordered && decoded.sequence == i;
		}
		producer.join();
		require(ordered, "Concurrent FIFO order changed");
		concurrent.pulse();
		concurrent.pulse();
		require(concurrent.await_tick(0, 1) == 2, "Frame ticks did not coalesce");
		require(concurrent.await_frame_tick(0, 1) == 0, "Capacity wakeup advanced host frame clock");
		concurrent.pulse_frame();
		concurrent.pulse_frame();
		require(concurrent.await_frame_tick(0, 1) == 2, "Host frame ticks did not coalesce");
		require(concurrent.await_tick(2, 1) == 4, "Host frame did not also wake capacity waiters");
		// Input arrivals have their own clock: they must wake input consumers
		// without causing an extra render pulse or capacity-clock increment.
		require(concurrent.await_input_tick(0, 1) == 0, "Frame/capacity wakes advanced input clock");
		concurrent.pulse_input();
		concurrent.pulse_input();
		require(concurrent.await_input_tick(0, 1) == 2, "Input ticks did not coalesce");
		require(concurrent.await_input_tick(2, 1) == 2, "Input timeout invented a tick");
		require(concurrent.await_frame_tick(2, 1) == 2, "Input arrival advanced host frame clock");
		require(concurrent.await_tick(4, 1) == 4, "Input arrival advanced capacity clock");
		concurrent.stop();
		concurrent.pulse_input(); // Stopped admission must stay stopped.
		require(concurrent.await_input_tick(2, 1) == -1, "Stop did not terminate input waiter");
		require(finishing.await_input_tick(0, 1) == -1, "Finish did not terminate input waiter");
		require(concurrent.await_frame_tick(2, 1) == -1, "Stop did not release host frame waiter");
		require(finishing.await_frame_tick(0, 1) == -1, "Finish did not release host frame waiter");
		std::cout << "FRAME_PROTOCOL_PASS: malformed/truncated input, atomic decode, backpressure, shutdown, 10000 concurrent frames\n";
		return 0;
	} catch (const std::exception &error) {
		std::cerr << error.what() << '\n';
		return 1;
	}
}
