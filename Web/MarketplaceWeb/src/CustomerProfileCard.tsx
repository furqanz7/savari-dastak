import { Mail, MapPin, Pencil, Phone, ShieldCheck } from "lucide-react";
import { AppleLogo } from "./IdentityProviderLogos";

export function CustomerProfileCard({ initials, displayName, phoneNumber, email, signInLabel, savedPlaceCount, onEdit }: {
  initials: string;
  displayName: string;
  phoneNumber: string;
  email?: string;
  signInLabel: string;
  savedPlaceCount: number;
  onEdit: () => void;
}) {
  return <button className="customer-identity-card" type="button" onClick={onEdit}
    aria-label="Edit profile" aria-describedby="customer-identity-name customer-identity-contacts customer-identity-meta">
    <span className="customer-identity-heading">
      <span className="customer-identity-avatar" aria-hidden="true">{initials}</span>
      <strong id="customer-identity-name">{displayName || "Your account"}</strong>
      <span className="customer-identity-edit" aria-hidden="true"><Pencil size={15} /><span>Edit</span></span>
    </span>
    <span className="customer-identity-contacts" id="customer-identity-contacts">
      <span className="customer-identity-phone"><Phone size={15} aria-hidden="true" /><span>{phoneNumber || "Add a contact number"}</span></span>
      {email && <span className="customer-identity-email"><Mail size={15} aria-hidden="true" /><span>{email}</span></span>}
    </span>
    <span className="customer-identity-meta" id="customer-identity-meta">
      <span>{signInLabel === "Apple sign-in" ? <AppleLogo /> : <ShieldCheck size={16} aria-hidden="true" />}<span>{signInLabel}</span></span>
      <span><MapPin size={16} aria-hidden="true" /><span>{savedPlaceCount} saved {savedPlaceCount === 1 ? "place" : "places"}</span></span>
    </span>
  </button>;
}
