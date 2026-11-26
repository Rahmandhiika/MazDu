import Foundation
import MultipeerConnectivity

@Observable
final class MultipeerManager: NSObject {
    static let serviceType = "duelmaze"

    /// A short, random suffix keeps host election deterministic without exposing the
    /// device name or exceeding `MCPeerID`'s 63-byte display-name limit.
    let peerID = MCPeerID(displayName: "Player#\(Int.random(in: 1000...9999))")
    let session: MCSession

    private(set) var connectedPeers: [MCPeerID] = []

    /// Set by whoever owns the match (MatchViewModel) to receive decoded messages —
    /// a direct callback rather than an observable "last message" property, since two
    /// consecutive equal-value messages (e.g. opponent stationary) wouldn't reliably
    /// re-trigger a SwiftUI `onChange`.
    var onMessage: ((NetworkMessage) -> Void)?

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var pendingPeer: MCPeerID?

    var isConnected: Bool { !connectedPeers.isEmpty }
    var localDisplayName: String { peerID.displayName }

    override init() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    /// Both devices advertise and browse at the same time — no Host/Join distinction,
    /// no manual invite/accept UI. Whoever finds a peer first invites it; the other
    /// side auto-accepts. First connection wins; searching stops once connected.
    func startAutoConnect() {
        pendingPeer = nil
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stopAutoConnect() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    func send(_ message: NetworkMessage) {
        guard let peer = session.connectedPeers.first, let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    /// D-063 item 3: explicit "leave the match" call (ready-check's diamond) — as
    /// opposed to `isConnected` dropping on its own from a real connection loss.
    /// Disconnecting the session is what flips the opponent's `isConnected` to false too.
    func disconnect() {
        session.disconnect()
        stopAutoConnect()
        pendingPeer = nil
    }
}

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peers = session.connectedPeers
        Task { @MainActor in
            connectedPeers = peers
            if !peers.isEmpty {
                stopAutoConnect()
            } else if pendingPeer == peerID {
                pendingPeer = nil
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(NetworkMessage.self, from: data) else { return }
        Task { @MainActor in
            onMessage?(message)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard session.connectedPeers.isEmpty, pendingPeer == nil || pendingPeer == peerID else {
            invitationHandler(false, nil)
            return
        }
        pendingPeer = peerID
        invitationHandler(true, session)
    }
}

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard session.connectedPeers.isEmpty, pendingPeer == nil else { return }
        pendingPeer = peerID
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
